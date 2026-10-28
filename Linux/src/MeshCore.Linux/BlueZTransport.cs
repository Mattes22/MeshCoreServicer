using Avalonia.Threading;
using MeshCore.Core;
using MeshCore.Linux.DBus;
using Tmds.DBus.Protocol;

namespace MeshCore.Linux;
public sealed record LinuxDevice(string Path, string Name, bool Paired, ulong Address)
{ public override string ToString() => Name + (Paired ? " · spárováno" : " · nespárováno"); }
public sealed class BlueZTransport : IMeshTransport, IBleDiagnosticsSource, IDisposable
{
    private DBusConnection? scan;
    private Adapter1? scanAdapter;
    private CancellationTokenSource? scanCancel;
    private readonly BleConnectionFlow flow = new();
    public List<LinuxDevice> Devices { get; } = [];
    public string State { get; private set; } = "Bluetooth: spusťte skenování";
    public string? Error => flow.LastFailure?.Message;
    public bool Ready => flow.TransportReady;
    public bool Connecting => flow.Connecting;
    public LinuxDevice? Device { get; private set; }
    public string ConnectionImplementation => "linux-bluez-dbus-1";
    public BleConnectionJournal ConnectionDiagnostics => flow.Journal;
    public int MaximumWriteLength => flow.Driver is BlueZConnection connection ? connection.MaximumWriteLength : 20;
    public event Action<byte[]>? Received;
    public event Action? Disconnected;
    public event Action? Changed;
    public Func<string,string?,Task<string?>> PairPrompt { get; set; } = (_,_) => Task.FromResult<string?>(null);
    public BlueZTransport()
    {
        flow.ResetTransport += () => Disconnected?.Invoke();
        flow.Changed += () => { State = flow.Connecting ? "Připojuji: " + BleText.Stage(flow.Stage) : flow.TransportReady ? "Připojeno přes Bluetooth" : "Companion odpojen"; Changed?.Invoke(); };
    }
    internal static DBusConnection SystemBus() => new(DBusAddress.System ?? throw new MeshException("Systémový D-Bus není dostupný. Spusťte aplikaci v desktopové relaci Linuxu."));
    public async Task Scan()
    {
        await StopScan(); Devices.Clear(); State = "Hledám BLE companiony…"; Changed?.Invoke();
        var bus = SystemBus(); scan = bus; var owner = scanCancel = new();
        try
        {
            await bus.ConnectAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(10));
            DBusService bluez = new(bus,"org.bluez");
            var objects = await bluez.CreateObjectManager("/").GetManagedObjectsAsync().WaitAsync(TimeSpan.FromSeconds(10));
            var adapterPath = objects.FirstOrDefault(p => p.Value.ContainsKey("org.bluez.Adapter1")).Key;
            if (adapterPath.ToString() is not { Length: > 1 }) throw new MeshException("Nenalezen Bluetooth adaptér. Ověřte službu bluetooth a připojený adaptér.");
            scanAdapter = bluez.CreateAdapter1(adapterPath);
            if (!await scanAdapter.GetPoweredAsync()) throw new MeshException("Bluetooth je vypnuté. Zapněte jej v nastavení systému.");
            await scanAdapter.SetDiscoveryFilterAsync(new() { ["Transport"] = "le", ["UUIDs"] = VariantValue.Array(new[] { Codec.Service.ToString() }) });
            await scanAdapter.StartDiscoveryAsync().WaitAsync(TimeSpan.FromSeconds(10));
            _ = Collect(bus,bluez,owner.Token);
        }
        catch { await StopScan(); throw; }
    }
    private async Task Collect(DBusConnection owner, DBusService bluez, CancellationToken token)
    {
        try {
            var end = DateTimeOffset.UtcNow.AddSeconds(20);
            while (!token.IsCancellationRequested && DateTimeOffset.UtcNow < end)
            {
                var objects = await bluez.CreateObjectManager("/").GetManagedObjectsAsync().WaitAsync(token);
                if (token.IsCancellationRequested) return;
                foreach (var (path,interfaces) in objects)
                    if (interfaces.TryGetValue("org.bluez.Device1",out var p) && p.TryGetValue("UUIDs",out var uuids) && uuids.GetArray<string>().Any(s => Guid.TryParse(s,out var id) && id == Codec.Service))
                    {
                        string id = path.ToString(); string name = p.TryGetValue("Alias",out var alias)?alias.GetString():p.TryGetValue("Name",out var deviceName)?deviceName.GetString():"MeshCore companion";
                        ulong address = ulong.Parse(p["Address"].GetString().Replace(":",""),System.Globalization.NumberStyles.HexNumber);
                        var item = new LinuxDevice(id,name,p["Paired"].GetBool(),address); int index = Devices.FindIndex(d => d.Path == id);
                        if (index >= 0) Devices[index] = item; else Devices.Add(item);
                    }
                Changed?.Invoke(); await Task.Delay(600,token);
            }
            if (!token.IsCancellationRequested && ReferenceEquals(scan,owner)) { await StopScan(); State = $"Skenování ukončeno · {Devices.Count} zařízení"; Changed?.Invoke(); }
        } catch (OperationCanceledException) { }
        catch { if(ReferenceEquals(scan,owner)){await StopScan(); State = "Skenování selhalo. Ověřte BlueZ, oprávnění a adaptér."; Changed?.Invoke();} }
    }
    public async Task StopScan()
    {
        scanCancel?.Cancel(); scanCancel?.Dispose(); scanCancel = null;
        var adapter = scanAdapter; scanAdapter = null; var bus = scan; scan = null;
        try { if (adapter != null) await adapter.StopDiscoveryAsync().WaitAsync(TimeSpan.FromSeconds(3)); } catch { }
        bus?.Dispose();
    }
    public async Task Pair(LinuxDevice device)
    {
        if (Connecting || Ready) throw new MeshException("Před párováním ukončete probíhající připojení.");
        await StopScan(); using var bus = SystemBus(); await bus.ConnectAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(10));
        DBusService bluez = new(bus,"org.bluez"); var agent = new PairingAgent(bus,PairPrompt); bus.AddMethodHandler(agent);
        var manager = bluez.CreateAgentManager1("/org/bluez"); await manager.RegisterAgentAsync(PairingAgent.AgentPath,"KeyboardDisplay");
        try { await bluez.CreateDevice1(device.Path).PairAsync().WaitAsync(TimeSpan.FromSeconds(90)); State = "Systémové párování dokončeno"; Changed?.Invoke(); }
        catch(TimeoutException){try{await bluez.CreateDevice1(device.Path).CancelPairingAsync().WaitAsync(TimeSpan.FromSeconds(3));}catch{}throw new MeshException("Párování nedokončeno v časovém limitu; před novým pokusem ověřte stav systému.");}
        finally { try { await manager.UnregisterAgentAsync(PairingAgent.AgentPath).WaitAsync(TimeSpan.FromSeconds(3)); } catch { } }
    }
    public async Task Connect(LinuxDevice device, Func<Task> initialize)
    {
        await StopScan(); Device = device;
        var driver = new BlueZConnection(device,flow,bytes => Received?.Invoke(bytes));
        await flow.Connect(driver,initialize);
    }
    public void Disconnect(BleCloseReason reason = BleCloseReason.User) => flow.Disconnect(reason);
    public Task WriteAsync(byte[] frame, CancellationToken cancellation = default) => flow.Driver is BlueZConnection connection ? connection.Write(frame,cancellation) : throw new MeshException("BLE není připojeno.");
    public void Dispose() { scanCancel?.Cancel(); scan?.Dispose(); flow.Disconnect(BleCloseReason.Shutdown); }
}
internal sealed class BlueZConnection(LinuxDevice target, BleConnectionFlow flow, Action<byte[]> receive) : IBleConnectionDriver, IBleMtuSource
{
    private DBusConnection? bus;
    private DBusService bluez;
    private Device1? device;
    private GattCharacteristic1? rx,tx;
    private string? servicePath;
    private readonly List<IDisposable> watchers = [];
    private bool disposed, observed, connectedByUs;
    private readonly CancellationTokenSource life = new();
    public int AttMtu { get; private set; } = 23;
    public int MaximumWriteLength => Math.Min(176,Math.Max(0,AttMtu-3));
    private void Dispatch(Action action) => Dispatcher.UIThread.Post(() => { if (!disposed && ReferenceEquals(flow.Driver,this)) { try { action(); } catch (Exception ex) { flow.Fault(this,ex,flow.Stage); } } });
    public async Task<BleEvidence> Execute(BleStage stage, CancellationToken token)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(token,life.Token); token = linked.Token;
        switch (stage)
        {
            case BleStage.OpenDevice:
                bus = BlueZTransport.SystemBus(); await bus.ConnectAsync().AsTask().WaitAsync(token);
                _ = WatchBus(bus);
                bluez = new(bus,"org.bluez"); device = bluez.CreateDevice1(target.Path); return new();
            case BleStage.Access:
                _ = await device!.GetPairedAsync().WaitAsync(token); return new(); // D-Bus/polkit enforces access; no chmod/privilege escalation.
            case BleStage.GattSession:
                await Watch(device!.WatchPropertiesChangedAsync(p => Dispatch(() => {
                    if (p.Connected == true) observed = true;
                    if (p.Connected == false && observed) flow.Lost(this,new());
                }),emitOnCapturedContext:false),token);
                observed = await device.GetConnectedAsync().WaitAsync(token);
                if (!observed) {connectedByUs=true;await device.ConnectAsync().WaitAsync(token);}
                while (!await device.GetServicesResolvedAsync().WaitAsync(token)) await Task.Delay(100,token);
                observed = true; return new();
            case BleStage.Service:
                var services = await bluez!.CreateObjectManager("/").GetManagedObjectsAsync().WaitAsync(token);
                servicePath = services.Where(p => p.Value.TryGetValue("org.bluez.GattService1",out var s) && s.TryGetValue("Device",out var d) && d.GetObjectPath().ToString() == target.Path && Guid.TryParse(s["UUID"].GetString(),out var uuid) && uuid == Codec.Service).Select(p => p.Key.ToString()).FirstOrDefault() ?? throw new BleStepException(BleReason.MissingService);
                return new();
            case BleStage.Characteristics:
                var chars = await bluez!.CreateObjectManager("/").GetManagedObjectsAsync().WaitAsync(token);
                foreach (var (path,interfaces) in chars)
                    if (interfaces.TryGetValue("org.bluez.GattCharacteristic1",out var p) && p["Service"].GetObjectPath().ToString() == servicePath)
                    {
                        var uuid = Guid.Parse(p["UUID"].GetString()); var flags = p["Flags"].GetArray<string>();
                        if (uuid == Codec.Rx && flags.Contains("write")) rx = bluez.CreateGattCharacteristic1(path);
                        if (uuid == Codec.Tx && flags.Contains("notify")) tx = bluez.CreateGattCharacteristic1(path);
                    }
                if (rx == null || tx == null) throw new BleStepException(BleReason.MissingCharacteristics); return new();
            case BleStage.Notifications:
                await Watch(tx!.WatchPropertiesChangedAsync(p => { if (p.HasValueChanged && p.Value is { } bytes) Dispatch(() => receive(bytes)); },emitOnCapturedContext:false),token);
                await tx.StartNotifyAsync().WaitAsync(token); return new();
            case BleStage.Mtu:
                AttMtu = await rx!.GetMTUAsync().WaitAsync(token);
                if (AttMtu < 179) throw new BleStepException(BleReason.MtuInsufficient,new(Mtu:AttMtu)); return new(Mtu:AttMtu);
            default: throw new InvalidOperationException();
        }
    }
    private async Task Watch(ValueTask<IDisposable> operation,CancellationToken token)
    {var watcher=await BleNativeOperation.Await(operation.AsTask(),token,w=>w.Dispose());if(disposed){watcher.Dispose();throw new OperationCanceledException(token);}watchers.Add(watcher);}
    private async Task WatchBus(DBusConnection owner)
    {try{await owner.DisconnectedAsync();Dispatch(()=>flow.Lost(this,new()));}catch{Dispatch(()=>flow.Lost(this,new()));}}
    public async Task Write(byte[] bytes, CancellationToken token)
    {
        if (disposed || rx == null) throw new MeshException("BLE není připojeno.");
        Codec.BleFrame(bytes,MaximumWriteLength); using var linked = CancellationTokenSource.CreateLinkedTokenSource(token,life.Token);
        await rx.WriteValueAsync(bytes,new() { ["type"] = "request" }).WaitAsync(linked.Token);
    }
    public void Dispose()
    {
        if (disposed) return; disposed = true; life.Cancel();
        foreach (var watcher in watchers) watcher.Dispose(); watchers.Clear();
        // Closing our system-bus connection releases only our GATT notification session.
        // Explicit Device.Disconnect also cancels this connection, but never unpairs/removes the device.
        if (connectedByUs && device != null) _ = device.DisconnectAsync().ContinueWith(t => { _ = t.Exception; },TaskScheduler.Default);
        bus?.Dispose(); life.Dispose();
    }
}
internal sealed class PairingAgent(DBusConnection bus, Func<string,string?,Task<string?>> prompt) : DBusHandler(bus,AgentPath,false,handleOnCapturedContext:false), IAgent1Handler
{
    public const string AgentPath = "/org/meshcoreservicer/agent";
    private static DBusErrorReplyException Rejected() => new("org.bluez.Error.Rejected","Párování odmítnuto uživatelem.");
    public ValueTask ReleaseAsync() => default;
    public async ValueTask<string> RequestPinCodeAsync(ObjectPath device) => await prompt("Zadejte PIN z vlastního zařízení",null) ?? throw Rejected();
    public async ValueTask<uint> RequestPasskeyAsync(ObjectPath device) => uint.TryParse(await prompt("Zadejte šestimístný PIN z vlastního zařízení",null),out var code) && code <= 999999 ? code : throw Rejected();
    public async ValueTask DisplayPinCodeAsync(ObjectPath device, string pin) { if (await prompt("Zadejte tento PIN na zařízení",pin) == null) throw Rejected(); }
    public async ValueTask DisplayPasskeyAsync(ObjectPath device, uint passkey, ushort entered) { if (await prompt("Zadejte tento PIN na zařízení",passkey.ToString("D6")) == null) throw Rejected(); }
    public async ValueTask RequestConfirmationAsync(ObjectPath device, uint passkey) { if (await prompt("Souhlasí PIN na obou zařízeních?",passkey.ToString("D6")) == null) throw Rejected(); }
    public async ValueTask RequestAuthorizationAsync(ObjectPath device) { if (await prompt("Povolit párování s vybraným zařízením?","") == null) throw Rejected(); }
    public ValueTask AuthorizeServiceAsync(ObjectPath device, string uuid) => Guid.TryParse(uuid,out var id) && id == Codec.Service ? default : ValueTask.FromException(Rejected());
    public ValueTask CancelAsync() => default;
}
