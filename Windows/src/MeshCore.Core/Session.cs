using System.Text;

namespace MeshCore.Core;

public interface IMeshTransport
{
    event Action<byte[]>? Received;
    event Action? Disconnected;
    int MaximumWriteLength => 176;
    Task WriteAsync(byte[] frame, CancellationToken cancellation = default);
}
public sealed class RequestRejectedException(byte code) : Exception($"Companion odmítl požadavek (kód {code}).");
public sealed class MeshSession : IDisposable
{
    private readonly IMeshTransport transport;
    private readonly SemaphoreSlim gate = new(1, 1);
    private readonly object sync = new();
    private readonly List<Frame> remote = [];
    private readonly HashSet<string> seen = [];
    private readonly TimeSpan localTimeout;
    private readonly RemoteRequestPacer pacer;
    private readonly ServiceTrafficGovernor traffic;
    private readonly Dictionary<string, ServiceRoute> routes = [];
    public event Action<string>? ServiceProgress;
    public ServiceRoute RouteFor(byte[] key) { lock (sync) return routes.GetValueOrDefault(Convert.ToHexStringLower(key), ServiceRoute.FloodOrUnknown); }
    public void BeginServiceOperation(Func<bool> valid) => traffic.Begin(valid);
    public void EndServiceOperation() => traffic.End();
    private readonly TimeSpan? remoteTimeout;
    private TaskCompletionSource<Frame>? pending;
    private Func<Frame, bool>? matching;
    private int generation;
    private bool serviceSending;
    private CancellationTokenSource serviceWait = new();
    public void CancelServiceWait() { var old = serviceWait; serviceWait = new(); old.Cancel(); old.Dispose(); }
    public bool RequiresReconnect { get; private set; }
    public event Action<Frame>? Event;
    public event Action? Malformed;
    public event Action<byte[], string, string>? CliReply;
    public MeshSession(IMeshTransport transport, TimeSpan? localTimeout = null, RemoteRequestPacer? pacer = null, TimeSpan? remoteTimeout = null, ServiceTrafficGovernor? traffic = null)
    {
        this.transport = transport; this.localTimeout = localTimeout ?? TimeSpan.FromSeconds(12); this.pacer = pacer ?? new(); this.remoteTimeout = remoteTimeout;
        this.traffic = traffic ?? new ServiceTrafficGovernor(this.pacer.clock, this.pacer.delay);
        transport.Received += Receive; transport.Disconnected += Reset;
    }
    public void Reset()
    {
        CancelServiceWait();
        lock (sync) { routes.Clear(); generation++; pending?.TrySetException(new IOException("Companion byl odpojen.")); pending = null; matching = null; remote.Clear(); seen.Clear(); RequiresReconnect = false; }
    }
    private void Receive(byte[] bytes)
    {
        Frame frame;
        try { frame = Codec.Decode(bytes); } catch (MeshException) { Malformed?.Invoke(); return; }
        bool duplicate;
        lock (sync)
        {
            if (frame.Code == 2) routes.Clear();
            if (frame.Payload is Contact contact) routes[contact.Id] = ServiceRouting.Classify(contact.PathLength, contact.Path.Length);
            if (frame.Code is 0x80 or 0x81 && frame.Prefix != null) routes.Remove(Convert.ToHexStringLower(frame.Prefix));
            if (serviceSending && frame.Payload is Receipt { Flood: true }) { traffic.ConfirmFlood(); routes.Clear(); }
            var identity = frame.Payload switch { Incoming m => m.Identity, ChannelIncoming m => m.Identity, _ => null };
            duplicate = identity != null && !seen.Add(identity);
            if (seen.Count > 4096) { seen.Clear(); if (identity != null) seen.Add(identity); }
            if (!duplicate && (frame.Code is 0x85 or 0x86 or 0x87 or 0x8c || frame.Payload is Incoming { Type: 1 }))
            { remote.Add(frame); if (remote.Count > 256) remote.RemoveAt(0); }

        }
        if (!duplicate) Event?.Invoke(frame);
        lock (sync)
        {
            if (frame.Code == 1) pending?.TrySetException(new RequestRejectedException((byte)frame.Payload!));
            else if (matching?.Invoke(frame) == true) pending?.TrySetResult(frame);
        }
    }
    private ServiceRoute? ServiceRouteFor(byte[] bytes)
    {
        lock (sync)
        {
            if (bytes[0] == 55) return ServiceRoute.FloodOrUnknown;
            if (bytes[0] is 26 or 27 or 50) return routes.GetValueOrDefault(Convert.ToHexStringLower(bytes.AsSpan(1, 32)), ServiceRoute.FloodOrUnknown);
            if (bytes[0] == 2 && bytes.Length >= 13 && bytes[1] == 1)
            {
                var command = Encoding.UTF8.GetString(bytes[13..]); if (command is "advert" or "advert.zerohop") return ServiceRoute.FloodOrUnknown;
                var prefix = Convert.ToHexStringLower(bytes.AsSpan(7, 6)); var matches = routes.Where(e => e.Key.StartsWith(prefix, StringComparison.Ordinal)).ToArray();
                return matches.Length == 1 ? matches[0].Value : ServiceRoute.FloodOrUnknown;
            }
            return null;
        }
    }
    private async Task<Frame> Exchange(byte[] bytes, Func<Frame, bool> predicate, TimeSpan? timeout = null, Func<byte[]>? rebuild = null, Func<Task>? prepare = null)
    {
        Codec.BleFrame(bytes, transport.MaximumWriteLength);
        var admittedRoute = ServiceRouteFor(bytes);
        if (admittedRoute is { } route)
        {
            int before = generation; await traffic.Acquire(route, text => ServiceProgress?.Invoke(text), serviceWait.Token);
            if (before != generation) throw new IOException("BLE relace se během čekání změnila; požadavek se neposlal.");
            if (ServiceRouteFor(bytes) != route) throw new MeshException("Trasa se během čekání změnila; požadavek se neposlal. Ověřte kontakt ručně.");
        }
        int preparedEpoch = generation; if (prepare != null) await prepare();
        if (preparedEpoch != generation) throw new IOException("BLE relace se během přípravy změnila; požadavek se neposlal.");
        if (admittedRoute != null) {
            if (ServiceRouteFor(bytes) != admittedRoute) throw new MeshException("Trasa se během přípravy změnila; požadavek se neposlal.");
            traffic.ValidateContext(); ClearRemote();
        }
        bytes = rebuild?.Invoke() ?? bytes; Codec.BleFrame(bytes, transport.MaximumWriteLength);
        serviceSending = ServiceRouteFor(bytes) != null;
        TaskCompletionSource<Frame> completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
        int epoch;
        lock (sync) { if (pending != null) throw new MeshException("Probíhá jiný požadavek."); epoch = generation; pending = completion; matching = predicate; }
        using var cancel = new CancellationTokenSource(timeout ?? localTimeout);
        try
        {
            await transport.WriteAsync(bytes, cancel.Token).WaitAsync(cancel.Token);
            return await completion.Task.WaitAsync(cancel.Token);
        }
        catch (Exception ex) when (ex is not RequestRejectedException)
        {
            lock (sync) { if (epoch == generation) RequiresReconnect = true; }
            if (ex is OperationCanceledException) throw new TimeoutException("Vypršel čas odpovědi; výsledek není známý. Obnovte BLE relaci a nejprve čtěte stav.");
            throw;
        }
        finally { serviceSending = false; lock (sync) { if (ReferenceEquals(pending, completion)) { pending = null; matching = null; } } }
    }
    private async Task<T> Operation<T>(Func<Task<T>> action)
    {
        if (!await gate.WaitAsync(0)) throw new MeshException("Probíhá jiný požadavek.");
        try
        {
            if (RequiresReconnect) throw new MeshException("Po timeoutu nelze bezpečně přiřadit další odpověď. Odpojte a znovu připojte companion; zápis neopakujte, nejprve načtěte stav.");
            int epoch = generation; var result = await action();
            if (epoch != generation) throw new IOException("BLE relace se během požadavku změnila.");
            return result;
        }
        finally { gate.Release(); }
    }
    private async Task Drain()
    {
        for (int n = 0; n < 128; n++)
        {
            var f = await Exchange([10], f => f.Code is 7 or 16 or 8 or 17 or 10 or 27);
            if (f.Code == 10) return;
        }
        throw new MeshException("Příliš mnoho čekajících zpráv; načtěte je znovu ručně.");
    }
    private async Task<Frame> Remote(TimeSpan timeout, Func<Frame, bool> predicate, bool poll = false)
    {
        var end = DateTimeOffset.UtcNow + (remoteTimeout ?? timeout); int epoch = generation;
        while (DateTimeOffset.UtcNow < end)
        {
            if (epoch != generation) throw new IOException("BLE relace se změnila.");
            lock (sync) { var index = remote.FindIndex(f => predicate(f)); if (index >= 0) { var f = remote[index]; remote.RemoveAt(index); pacer.ReplyReceived(); return f; } }
            if (poll) await Drain();
            lock (sync) { var index = remote.FindIndex(f => predicate(f)); if (index >= 0) { var f = remote[index]; remote.RemoveAt(index); pacer.ReplyReceived(); return f; } }
            await Task.Delay(300);
        }
        RequiresReconnect = true; throw new TimeoutException("Repeater neodpověděl v časovém limitu. Výsledek není známý; obnovte BLE relaci.");
    }
    private void ClearRemote() { lock (sync) remote.Clear(); }
    private async Task<uint> WaitRemoteSlot()
    {
        int epoch = generation; var timestamp = await pacer.Next();
        if (epoch != generation) throw new IOException("BLE relace se během čekání změnila; požadavek nebyl odeslán.");
        return timestamp;
    }
    private async Task<TimeSpan> Send(byte[] bytes, bool cli = false, Func<byte[]>? rebuild = null, Func<Task>? prepare = null)
    { var r = (Receipt)(await Exchange(bytes, f => f.Code == 6, rebuild: rebuild, prepare: prepare)).Payload!; return cli ? RemoteRequestPacer.CliResponseTimeout(r.Timeout) : TimeSpan.FromSeconds(Math.Clamp(r.Timeout / 1000d + 5, 10, 180)); }
    public Task<bool> Initialize() => Operation(async () =>
    {
        await Exchange([22, 3], f => f.Code == 13);
        await Exchange([1, 1, 0, 0, 0, 0, 0, 0, .. Encoding.UTF8.GetBytes("MeshCore Servicer")], f => f.Code == 5);
        await Exchange([20], f => f.Code == 12); return true;
    });
    public Task<bool> Contacts() => Operation(async () => { await Exchange([4], f => f.Code == 4, TimeSpan.FromSeconds(45)); return true; });
    public Task<bool> Contact(byte[] key) => Operation(async () => { await Exchange([30, .. key], f => f.Payload is Contact c && c.Key.SequenceEqual(key)); return true; });
    public Task<bool> AddContact(Contact c) => Operation(async () => { await Exchange(Codec.AddContact(c), f => f.Code == 0); return true; });
    public Task<bool> Discover(uint tag, Action? onSend = null) => Operation(async () => { await Exchange([55, 0x80, 0x04, .. Codec.U32(tag)], f => f.Code == 0, rebuild: () => { onSend?.Invoke(); return [55, 0x80, 0x04, .. Codec.U32(tag)]; }); return true; });
    public Task<bool> Channels(byte count) => Operation(async () =>
    { for (int i = 0; i < count; i++) { var index = (byte)i; await Exchange([31, index], f => f.Payload is ChannelInfo c && c.Index == index); } return true; });
    public Task<bool> SyncMessages() => Operation(async () => { await Drain(); return true; });
    public Task<Receipt> SendDirect(byte[] key, string text, uint timestamp) => Operation(async () => (Receipt)(await Exchange(Codec.Direct(key, text, timestamp), f => f.Code == 6)).Payload!);
    public Task<bool> SendChannel(byte index, string text, string sender, uint timestamp) => Operation(async () => { await Exchange(Codec.SendChannel(index, text, sender, timestamp), f => f.Code == 0); return true; });
    public Task<byte> Login(byte[] key, string password) => Operation(async () =>
    {
        await WaitRemoteSlot(); ClearRemote(); var timeout = await Send(Codec.Login(key, password));
        var f = await Remote(timeout, f => f.Code is 0x85 or 0x86 && f.Prefix!.SequenceEqual(key[..6]));
        if (f.Code == 0x86) throw new MeshException("Repeater odmítl přihlášení."); return (byte)f.Payload!;
    });
    public Task<RepeaterStatus> Status(byte[] key, Action? onSend = null) => Operation(async () =>
    { await WaitRemoteSlot(); ClearRemote(); var timeout = await Send([27, .. key], rebuild: () => { onSend?.Invoke(); return [27, .. key]; }); return (RepeaterStatus)(await Remote(timeout, f => f.Code == 0x87 && f.Prefix!.SequenceEqual(key[..6]))).Payload!; });
    public Task<byte[]> Binary(byte[] key, byte[] payload) => Operation(async () =>
    {
        if (key.Length != 32 || payload.Length is < 1 or > 140) throw new MeshException("Neplatný binární požadavek.");
        await WaitRemoteSlot(); ClearRemote(); var sent = (Receipt)(await Exchange([50, .. key, .. payload], f => f.Code == 6)).Payload!;
        return (byte[])(await Remote(TimeSpan.FromSeconds(Math.Clamp(sent.Timeout / 1000d + 5, 10, 180)), f => f.Code == 0x8c && f.Tag == sent.Ack)).Payload!;
    });
    public Task<string> Cli(byte[] key, string command, bool noReply = false, Func<string>? commandAtSend = null) => Operation(async () =>
    {
        var timestamp = await WaitRemoteSlot(); string actualCommand = command;
        var timeout = await Send(Codec.Direct(key, command, timestamp, true), cli: true, rebuild: () => { actualCommand = commandAtSend?.Invoke() ?? command; return Codec.Direct(key, actualCommand, (uint)pacer.clock.GetUtcNow().ToUnixTimeSeconds(), true); }, prepare: Drain);
        if (noReply) return "Přijato companionem; tento příkaz nemá vzdálenou odpověď. Provedení není potvrzené.";
        var f = await Remote(timeout, f => f.Payload is Incoming m && m.Type == 1 && m.Prefix.SequenceEqual(key[..6]), true);
        var text = ((Incoming)f.Payload!).Text; CliReply?.Invoke(key, actualCommand, text); return text;
    });
    public void Dispose() { transport.Received -= Receive; transport.Disconnected -= Reset; Reset(); gate.Dispose(); }
}
