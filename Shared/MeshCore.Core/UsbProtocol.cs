using System.Text;

namespace MeshCore.Core;

/// MeshCore 1.18.0 / 81dbae592ffad40b4212bc0b37e82b38da08f4bc.
/// Serial companion: '<' + uint16 LE + payload to radio, '>' from radio.
public sealed class UsbFrameDecoder
{
    public const int MaximumPayload = 176;
    private readonly List<byte> buffer = [];
    public static byte[] Encode(byte[] payload)
    {
        if (payload.Length is < 1 or > MaximumPayload) throw new MeshException("USB rámec musí mít 1–176 bajtů; nesmí se dělit.");
        return [0x3c, (byte)payload.Length, 0, .. payload];
    }
    public IReadOnlyList<byte[]> Feed(ReadOnlySpan<byte> bytes)
    {
        List<byte[]> frames = [];
        foreach (var value in bytes)
        {
            buffer.Add(value);
            while (buffer.Count >= 3)
            {
                if (buffer[0] != 0x3e) { buffer.RemoveAt(0); continue; }
                int length = buffer[1] | buffer[2] << 8;
                if (length is < 1 or > MaximumPayload) throw new MeshException("Neplatná délka USB rámce. Odpojte zařízení a ověřte USB companion firmware.");
                if (buffer.Count < length + 3) break;
                frames.Add(buffer.GetRange(3,length).ToArray()); buffer.RemoveRange(0,length+3);
            }
        }
        return frames;
    }
    public void Reset() => buffer.Clear();
}

/// Bounded UTF-8 line parser; partial Unicode codepoints remain buffered until LF.
public sealed class UsbLineDecoder
{
    private readonly List<byte> buffer = [];
    private static readonly UTF8Encoding Utf8 = new(false,true);
    public IReadOnlyList<string> Feed(ReadOnlySpan<byte> bytes)
    {
        List<string> lines=[];
        foreach(var b in bytes)
        {
            if(b==10) { lines.Add(Utf8.GetString(buffer.ToArray()).TrimEnd('\r')); buffer.Clear(); }
            else { if(buffer.Count>=2048)throw new MeshException("Příliš dlouhý řádek USB CLI; relace byla ukončena."); buffer.Add(b); }
        }
        return lines;
    }
    public void Reset()=>buffer.Clear();
}

public interface IUsbByteConnection
{
    event Action<byte[]>? Bytes;
    event Action? Closed;
    bool Ready { get; }
    Task WriteBytes(byte[] bytes, CancellationToken token=default);
}

/// No unbounded queue and no idle-time guesswork: firmware reflects a 2-character tag.
/// Timeout poisons the session; explicit reconnect clears parser state, never the tag counter.
public sealed class UsbRepeaterSession : IDisposable
{
    private readonly IUsbByteConnection port;
    private readonly UsbLineDecoder decoder=new();
    private readonly TimeProvider clock;
    private readonly TimeSpan timeout;
    private readonly object sync=new();
    private TaskCompletionSource<string>? pending;
    private string? expected;
    private int nextTag,epoch;
    public bool RequiresReconnect { get; private set; }
    public UsbRepeaterSession(IUsbByteConnection port, TimeProvider? clock=null, TimeSpan? timeout=null)
    {this.port=port;this.clock=clock??TimeProvider.System;this.timeout=timeout??TimeSpan.FromSeconds(8);port.Bytes+=Receive;port.Closed+=Reset;}
    public void Reset()
    {lock(sync){epoch++;pending?.TrySetException(new IOException("USB repeater byl odpojen."));pending=null;expected=null;RequiresReconnect=false;decoder.Reset();}}
    private void Receive(byte[] bytes)
    {
        lock(sync)
        {
            try
            {
                foreach(var line in decoder.Feed(bytes))
                {
                    var text=line.TrimStart();
                    if(expected!=null && text.StartsWith("-> "+expected,StringComparison.Ordinal))
                        pending?.TrySetResult(text[(3+expected.Length)..].Trim());
                }
            }
            catch {RequiresReconnect=true;pending?.TrySetException(new MeshException("USB CLI odpověď není platná; obnovte spojení."));}
        }
    }
    public static bool ReadOnly(string command)=> !Commands.Sensitive(command) &&
        (command is "stats-core" or "stats-radio" or "stats-packets" || Commands.ReadOnly(command));
    public static void Validate(string command)
    {
        if(string.IsNullOrWhiteSpace(command)||Encoding.UTF8.GetByteCount(command)>154 || command.Any(c=>char.IsControl(c)))
            throw new MeshException("USB příkaz musí být jeden řádek do 154 UTF-8 bajtů, bez řídicích znaků.");
        if(command.Contains('|')&&!command.StartsWith("set owner.info ",StringComparison.Ordinal))throw new MeshException("Znak | je povolen pouze uvnitř hodnoty owner.info.");
        var parts=command.Split(' ',StringSplitOptions.RemoveEmptyEntries);
        bool privateField=parts.Length>1 && parts[0] is "get" or "set" && new[]{"prv","private","secret","password","pin"}.Any(x=>parts[1].Contains(x,StringComparison.OrdinalIgnoreCase));
        // Raw dumps bypass the tagged reply and could expose private keys or packet data.
        if(command is "erase" or "log" || command.StartsWith("region load",StringComparison.Ordinal) || command=="get acl" || privateField&&!command.StartsWith("set guest.password ",StringComparison.Ordinal))
            throw new MeshException("Tento příkaz není v USB konzoli podporovaný (nepárovaný výpis, citlivé klíče nebo mazání).");
        Commands.ValidateCommand(command,154);
    }
    public async Task<string> Command(string command,CancellationToken cancellation=default)
    {
        Validate(command);TaskCompletionSource<string> completion;string tag;int generation;
        lock(sync)
        {
            if(!port.Ready)throw new IOException("USB zařízení není připojeno.");
            if(pending!=null)throw new MeshException("Probíhá USB příkaz. Další příkaz nebyl zařazen do fronty.");
            if(RequiresReconnect)throw new MeshException("Obnovte USB spojení; před dalším zápisem načtěte stav.");
            if(nextTag>=3844)throw new MeshException("Došly jedinečné značky USB CLI; restartujte aplikaci.");
            const string alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
            tag=""+alphabet[nextTag/62]+alphabet[nextTag%62]+"|";nextTag++;expected=tag;generation=epoch;
            pending=completion=new(TaskCreationOptions.RunContinuationsAsynchronously);
        }
        try
        {
            await port.WriteBytes(Encoding.UTF8.GetBytes(tag+command+"\r"),cancellation).WaitAsync(timeout,clock,cancellation);
            if(Commands.NoReply(command)) {lock(sync){RequiresReconnect=true;}return "Odesláno po USB; restart/vypnutí nemá potvrzující odpověď. Znovu připojte zařízení.";}
            return await completion.Task.WaitAsync(timeout,clock,cancellation);
        }
        catch(TimeoutException) {lock(sync){if(generation==epoch)RequiresReconnect=true;}throw new TimeoutException("USB repeater neodpověděl označenou odpovědí. Výsledek není známý. Ověřte firmware/režim, odpojte a znovu připojte; příkaz neopakujte automaticky.");}
        catch {lock(sync){if(generation==epoch)RequiresReconnect=true;}throw;}
        finally {lock(sync){if(ReferenceEquals(pending,completion)){pending=null;expected=null;}}}
    }
    public void Dispose(){port.Bytes-=Receive;port.Closed-=Reset;Reset();}
}

/// Keeps USB frames out of BLE sessions and ignores callbacks from the inactive link.
public interface IUsbDiagnosticsSource { IReadOnlyList<UsbDiagnostic> UsbDiagnostics {get;} string ActiveTransport {get;} bool UsbConnected {get;} }
public sealed class TransportRouter : IMeshTransport, IBleDiagnosticsSource, IUsbDiagnosticsSource
{
    private readonly IMeshTransport ble,usb;
    public bool IsUsb {get;private set;}
    public bool UsbConnected => usb is UsbTransport {Ready:true};
    public IReadOnlyList<UsbDiagnostic> UsbDiagnostics=>(usb as UsbTransport)?.Diagnostics.ToArray()??[];
    public string ActiveTransport=>IsUsb ? (usb is UsbTransport {Mode:UsbMode.Repeater}?"USB repeater":"USB companion") : "BLE companion";
    public event Action<byte[]>? Received;
    public event Action? Disconnected;
    public int MaximumWriteLength=>(IsUsb?usb:ble).MaximumWriteLength;
    public BleConnectionJournal ConnectionDiagnostics {get;}
    public string ConnectionImplementation=>IsUsb ? (usb is UsbTransport {Mode:UsbMode.Repeater} ? "USB serial repeater CLI 1.18" : "USB serial companion 1.18") : (ble as IBleDiagnosticsSource)?.ConnectionImplementation ?? "BLE";
    public TransportRouter(IMeshTransport ble,IMeshTransport usb)
    {
        this.ble=ble;this.usb=usb;ConnectionDiagnostics=(ble as IBleDiagnosticsSource)?.ConnectionDiagnostics??new();
        ble.Received+=data=>{if(!IsUsb)Received?.Invoke(data);};usb.Received+=data=>{if(IsUsb)Received?.Invoke(data);};
        ble.Disconnected+=()=>{if(!IsUsb)Disconnected?.Invoke();};usb.Disconnected+=()=>{if(IsUsb)Disconnected?.Invoke();};
    }
    public void SelectUsb(bool value){if(IsUsb==value)return;Disconnected?.Invoke();IsUsb=value;}
    public Task WriteAsync(byte[] frame,CancellationToken cancellation=default)=>(IsUsb?usb:ble).WriteAsync(frame,cancellation);
}
