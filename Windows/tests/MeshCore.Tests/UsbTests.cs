using System.Collections.Concurrent;
using System.Text;
using MeshCore.Core;

internal sealed class UsbBytesFake : IUsbByteConnection
{
    public event Action<byte[]>? Bytes;
    public event Action? Closed;
    public bool Ready {get;set;}=true;
    public List<byte[]> Sent {get;}=[];
    public Action<byte[]>? Handle {get;set;}
    public void Emit(string text)=>Bytes?.Invoke(Encoding.UTF8.GetBytes(text));
    public void Drop(){Ready=false;Closed?.Invoke();}
    public Task WriteBytes(byte[] bytes,CancellationToken token=default){token.ThrowIfCancellationRequested();Sent.Add(bytes);Handle?.Invoke(bytes);return Task.CompletedTask;}
}
internal sealed class SerialFake : ISerialEndpoint
{
    private readonly BlockingCollection<byte[]> input=new();
    public Action? Opening;
    public Action<byte[]>? Writing;
    public int Disposed;
    public void Open()=>Opening?.Invoke();
    public int Read(byte[] buffer){if(!input.TryTake(out var bytes,100))throw new TimeoutException();bytes.CopyTo(buffer,0);return bytes.Length;}
    public void Feed(byte[] bytes)=>input.Add(bytes);
    public void Write(byte[] bytes)=>Writing?.Invoke(bytes);
    public void Dispose(){Interlocked.Increment(ref Disposed);input.CompleteAdding();}
}
internal sealed class UsbClock : TimeProvider
{
    private DateTimeOffset now=DateTimeOffset.UnixEpoch;
    private readonly List<Timer> timers=[];
    public override DateTimeOffset GetUtcNow()=>now;
    public override ITimer CreateTimer(TimerCallback callback,object? state,TimeSpan dueTime,TimeSpan period)
    {var timer=new Timer(this,callback,state,dueTime,period);lock(timers)timers.Add(timer);return timer;}
    public int Pending {get{lock(timers)return timers.Count(t=>t.Due!=null);}}
    public void Advance(TimeSpan duration){now+=duration;Timer[] due;lock(timers)due=timers.Where(t=>t.Due<=now).ToArray();foreach(var t in due)t.Fire();}
    private sealed class Timer(UsbClock clock,TimerCallback callback,object? state,TimeSpan dueTime,TimeSpan period):ITimer
    {
        private readonly TimeSpan interval=period;
        public DateTimeOffset? Due=dueTime==Timeout.InfiniteTimeSpan?null:clock.now+dueTime;
        public bool Change(TimeSpan due,TimeSpan interval){Due=due==Timeout.InfiniteTimeSpan?null:clock.now+due;return true;}
        public void Fire(){Due=interval==Timeout.InfiniteTimeSpan?null:clock.now+interval;callback(state);}
        public void Dispose()=>Due=null;
        public ValueTask DisposeAsync(){Dispose();return ValueTask.CompletedTask;}
    }
}
internal static partial class Program
{
    private static async Task Until(Func<bool> condition){using var cancel=new CancellationTokenSource(TimeSpan.FromSeconds(3));while(!condition())await Task.Delay(1,cancel.Token);}
    private static async Task UsbTests()
    {
        await Test("USB companion wire direction and exact length",()=>{Bytes([60,2,0,22,3],UsbFrameDecoder.Encode([22,3]));Throws(()=>UsbFrameDecoder.Encode([]));Throws(()=>UsbFrameDecoder.Encode(new byte[177]));});
        await Test("USB stream handles every split, multiple frames and payload markers",()=>
        {byte[] stream=[99,0,62,4,0,62,60,0,255,62,1,0,10];for(int split=0;split<=stream.Length;split++){UsbFrameDecoder parser=new();var frames=parser.Feed(stream[..split]).Concat(parser.Feed(stream[split..])).ToArray();Equal(2,frames.Length);Bytes([62,60,0,255],frames[0]);Bytes([10],frames[1]);}});
        await Test("USB malformed sizes fail closed and decoder reset discards fragments",()=>{foreach(var length in new[]{0,177,65535}){UsbFrameDecoder parser=new();Throws(()=>parser.Feed([62,(byte)length,(byte)(length>>8)]));}UsbFrameDecoder p=new();p.Feed([62,2]);p.Reset();Bytes([10],p.Feed([62,1,0,10]).Single());});
        await Test("USB CLI handles split UTF8 and rejects unbounded or invalid lines",()=>{UsbLineDecoder parser=new();var bytes=Text("  -> AA|Příliš žluťoučký\r\n");List<string> lines=[];foreach(var b in bytes)lines.AddRange(parser.Feed([b]));Equal("  -> AA|Příliš žluťoučký",lines.Single());Throws(()=>new UsbLineDecoder().Feed(new byte[2049]));try{new UsbLineDecoder().Feed([255,10]);throw new Exception("Invalid UTF8 accepted");}catch(DecoderFallbackException){}});
        await Test("USB CLI injection and private dumps never write",async()=>{UsbRepeaterSession.Validate(new string('x',154));UsbRepeaterSession.Validate("set owner.info Monkey | public contact");UsbBytesFake port=new();using UsbRepeaterSession cli=new(port);foreach(var command in new[]{"ver\rreboot","get name\nreboot","AB|reboot","get prv.key","get acl","erase","log","region load",new string('ě',78)})await Fails(()=>cli.Command(command));Equal(0,port.Sent.Count);});
        await Test("USB tagged replies ignore echo, unrelated tags and debug output",async()=>
        {UsbBytesFake port=new();using UsbRepeaterSession cli=new(port);var task=cli.Command("get name");string tag=Encoding.UTF8.GetString(port.Sent.Single())[..3];port.Emit(tag+"get name\r\n  -> XX|wrong\r\nboot debug\n");Assert(!task.IsCompleted);port.Emit("  -> "+tag+"> Žluťoučký\r\n");Equal("> Žluťoučký",await task);});
        await Test("USB CLI rejects simultaneous commands without queue",async()=>{UsbBytesFake port=new();using UsbRepeaterSession cli=new(port);var first=cli.Command("ver");await Fails(()=>cli.Command("board"));Equal(1,port.Sent.Count);port.Drop();await Fails(()=>first);});
        await Test("USB CLI timeout uses controlled time and never retries",async()=>{UsbClock clock=new();UsbBytesFake port=new();using UsbRepeaterSession cli=new(port,clock);var first=cli.Command("ver");clock.Advance(TimeSpan.FromSeconds(9));await Fails(()=>first);Assert(cli.RequiresReconnect);await Fails(()=>cli.Command("board"));Equal(1,port.Sent.Count);});
        await Test("USB new session does not reuse tags or accept a late old reply",async()=>
        {UsbBytesFake port=new();using UsbRepeaterSession cli=new(port);var first=cli.Command("ver");string old=Encoding.UTF8.GetString(port.Sent[^1])[..3];cli.Reset();await Fails(()=>first);var next=cli.Command("board");string current=Encoding.UTF8.GetString(port.Sent[^1])[..3];Assert(old!=current);port.Emit("  -> "+old+"old\r\n");Assert(!next.IsCompleted);port.Emit("  -> "+current+"RAK\r\n");Equal("RAK",await next);});
        await Test("USB restart reports unconfirmed send and poisons further commands",async()=>{UsbBytesFake port=new();using UsbRepeaterSession cli=new(port);Assert((await cli.Command("reboot")).Contains("nemá potvrzující"));Assert(cli.RequiresReconnect);await Fails(()=>cli.Command("ver"));Equal(1,port.Sent.Count);});
        await Test("Transport switch isolates inactive bytes and resets the active session",()=>{Fake ble=new(),usb=new();TransportRouter router=new(ble,usb);int received=0,closed=0;router.Received+=_=>received++;router.Disconnected+=()=>closed++;usb.Emit([10]);ble.Emit([10]);Equal(1,received);router.SelectUsb(true);Equal(1,closed);ble.Emit([10]);ble.Drop();Equal(1,received);Equal(1,closed);usb.Emit([10]);Equal(2,received);});
        await Test("USB open failure has safe text, cleanup and supports another attempt",async()=>
        {SerialFake bad=new(){Opening=()=>throw new Exception("")},good=new();int n=0;using UsbTransport usb=new(factory:_=>n++==0?bad:good);await Fails(()=>usb.Open("fake",UsbMode.Companion));Assert(!usb.Connecting&&!usb.Ready);Assert(usb.Error?.Contains("USB-OPEN")==true);Equal(1,bad.Disposed);await usb.Open("fake",UsbMode.Companion);Assert(usb.Ready);usb.Disconnect();await Until(()=>good.Disposed>0);});
        await Test("Late native USB open is disposed after timeout and cannot revive connection",async()=>
        {UsbClock clock=new();using ManualResetEventSlim release=new();SerialFake slow=new(){Opening=()=>release.Wait()};using UsbTransport usb=new(factory:_=>slow,clock:clock);var opening=usb.Open("fake",UsbMode.Companion);await Until(()=>clock.Pending>0);clock.Advance(TimeSpan.FromSeconds(11));await Fails(()=>opening);Assert(!usb.Ready&&!usb.Connecting);release.Set();await Until(()=>slow.Disposed>0);Assert(!usb.Ready);});
        await Test("USB native abstraction sends whole frames and initializes without LoRa",async()=>
        {SerialFake endpoint=new();List<byte> codes=[];endpoint.Writing=bytes=>{Equal((byte)60,bytes[0]);Equal(bytes.Length-3,bytes[1]|bytes[2]<<8);byte code=bytes[3];codes.Add(code);byte[] reply=code switch{22=>Device(),1=>Own(),20=>[12,0,16],_=>throw new Exception("Unexpected LoRa operation")};endpoint.Feed([62,(byte)reply.Length,0,..reply]);};using UsbTransport usb=new(factory:_=>endpoint);using MeshSession session=new(usb);await usb.Open("fake",UsbMode.Companion);await session.Initialize();Assert(codes.SequenceEqual(new byte[]{22,1,20}));});
        await Test("USB repeater mode rejects companion commands before native write",async()=>{SerialFake endpoint=new(){Writing=_=>throw new Exception("Must not write")};using UsbTransport usb=new(factory:_=>endpoint);await usb.Open("fake",UsbMode.Repeater);Throws(()=>usb.WriteAsync([22,3]));});
        await Test("USB identity reuses profile without erasing its BLE address or history",async()=>{var (_,model)=await Model();int count=model.Library.Profiles.Count;await model.Initialize(0,propagateFailure:true);Equal(count,model.Library.Profiles.Count);Equal(123ul,model.Profile!.BluetoothAddress);Assert(!model.Monitoring);});
        await Test("USB local management only reads at initialization and verifies one setting",async()=>
        {
            SerialFake endpoint=new();List<string> commands=[];string name="Original";
            endpoint.Writing=bytes=>{string wire=Encoding.UTF8.GetString(bytes),tag=wire[..3],command=wire[3..].TrimEnd('\r');commands.Add(command);string reply=command switch {"ver"=>"v1.18.0","board"=>"RAK4631","get name"=>"> "+name,"set name Changed"=>"OK",_=>"Unknown command"};if(command=="set name Changed")name="Changed";endpoint.Feed(Text("  -> "+tag+reply+"\r\n"));};
            using UsbTransport usb=new(factory:_=>endpoint);using MeshSession companion=new(new Fake());UsbRepeaterController model=new(usb,companion);await usb.Open("fake",UsbMode.Repeater);await model.Initialize();Assert(commands.SequenceEqual(new[]{"ver","board","get name"}));Equal("Original",model.Name);model.Confirm=(_,_)=>Task.FromResult(false);await model.Apply("name","Changed");Equal(3,commands.Count);model.Confirm=(_,_)=>Task.FromResult(true);await model.Apply("name","Changed");Equal("Changed",model.Values["name"]);Assert(commands.TakeLast(2).SequenceEqual(new[]{"set name Changed","get name"}));
        });
        await Test("USB export works after failed open without port, payload or raw exception",async()=>
        {
            SerialFake endpoint=new(){Opening=()=>throw new IOException("private-port SECRET-PAYLOAD")};using UsbTransport usb=new(factory:_=>endpoint);TransportRouter router=new(new Fake(),usb);Controller model=new(router,new MemoryCredentials());router.SelectUsb(true);await Fails(()=>usb.Open("private-port",UsbMode.Companion));string json=model.BleDiagnosticReport();Assert(json.Contains("UsbConnection"));Assert(json.Contains("failed"));Assert(!json.Contains("private-port")&&!json.Contains("SECRET-PAYLOAD"));Assert(usb.Diagnostics.Any(d=>d.HResult!=null));
        });
        await Test("USB repeater diagnostics distinguish physical USB from companion initialization",async()=>{SerialFake endpoint=new();using UsbTransport usb=new(factory:_=>endpoint);TransportRouter link=new(new Fake(),usb);Controller controller=new(link,new MemoryCredentials());link.SelectUsb(true);await usb.Open("fake",UsbMode.Repeater);Assert(!controller.Initialized);using var report=System.Text.Json.JsonDocument.Parse(controller.DiagnosticReport());Assert(report.RootElement.GetProperty("Connected").GetBoolean());Equal("USB repeater",report.RootElement.GetProperty("ActiveTransport").GetString());Equal(0,report.RootElement.GetProperty("HardwareTests").GetArrayLength());});
        await Test("USB local reads do not consume remote service budget",async()=>{AdvancingClock clock=new();Fake t=new();LocalReplies(t);using MeshSession session=new(t,traffic:new(clock,clock.Delay));await session.Initialize();Equal(0,clock.Waits.Count);await session.ReserveDirectRadio();await session.ReserveDirectRadio();Equal(TimeSpan.FromSeconds(60),clock.Waits.Single());});
    }
}
