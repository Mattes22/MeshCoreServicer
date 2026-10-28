using System.IO.Ports;

namespace MeshCore.Core;

public enum UsbMode { Companion, Repeater }
public interface ISerialEndpoint : IDisposable
{
    void Open();
    int Read(byte[] buffer);
    void Write(byte[] bytes);
}
internal sealed class SerialEndpoint(string name) : ISerialEndpoint
{
    // No reset/bootloader sequence, no RTS pulse, no handshake.
    private readonly SerialPort port=new(name,115200,Parity.None,8,StopBits.One)
    {Handshake=Handshake.None,DtrEnable=true,RtsEnable=false,ReadTimeout=500,WriteTimeout=3000};
    public void Open(){port.Open();port.DiscardInBuffer();}
    public int Read(byte[] bytes)=>port.Read(bytes,0,bytes.Length);
    public void Write(byte[] bytes)=>port.Write(bytes,0,bytes.Length);
    public void Dispose()=>port.Dispose();
}
public record UsbDiagnostic(DateTimeOffset Date,string Phase,string Outcome,int? HResult=null);

/// Native serial I/O is off the UI thread. Epoch checks reject late callbacks/opens.
public sealed class UsbTransport : IMeshTransport,IUsbByteConnection,IDisposable
{
    private readonly Action<Action> dispatch;
    private readonly Func<string,ISerialEndpoint> factory;
    private readonly TimeSpan openTimeout;
    private readonly TimeProvider clock;
    private readonly UsbFrameDecoder frames=new();
    private readonly SemaphoreSlim opening=new(1,1),writing=new(1,1);
    private ISerialEndpoint? endpoint;
    private CancellationTokenSource? lifetime;
    private int epoch;
    public bool Ready {get;private set;}
    public bool Connecting {get;private set;}
    public UsbMode Mode {get;private set;}
    public string State {get;private set;}="USB odpojeno";
    public string? Error {get;private set;}
    public List<UsbDiagnostic> Diagnostics {get;}=[];
    public event Action? Changed;
    public event Action<byte[]>? Received;
    public event Action<byte[]>? Bytes;
    public event Action? Disconnected;
    public event Action? Closed;
    public int MaximumWriteLength=>UsbFrameDecoder.MaximumPayload;
    public UsbTransport(Action<Action>? dispatch=null,Func<string,ISerialEndpoint>? factory=null,TimeSpan? openTimeout=null,TimeProvider? clock=null)
    {this.clock=clock??TimeProvider.System;this.dispatch=dispatch??(action=>action());this.factory=factory??(name=>new SerialEndpoint(name));this.openTimeout=openTimeout??TimeSpan.FromSeconds(10);}
    public static string[] Ports()=>SerialPort.GetPortNames().Order(StringComparer.OrdinalIgnoreCase).ToArray();
    private void Record(string phase,string outcome,Exception? error=null)
    {Diagnostics.Add(new(DateTimeOffset.UtcNow,phase,outcome,error?.HResult));if(Diagnostics.Count>200)Diagnostics.RemoveAt(0);}
    public async Task Open(string name,UsbMode mode)
    {
        if(string.IsNullOrWhiteSpace(name))throw new MeshException("Vyberte sériový port USB zařízení.");
        if(!await opening.WaitAsync(0))throw new MeshException("Probíhá otevření USB portu; další pokus nebyl zařazen.");
        ISerialEndpoint? candidate=null;Task? operation=null;bool transferred=false;
        try
        {
            Disconnect();Mode=mode;Connecting=true;Error=null;State="Otevírám USB port…";Changed?.Invoke();Record("open","started");
            lifetime=new();var token=lifetime.Token;int generation=epoch;
            candidate=factory(name);var owned=candidate;operation=Task.Run(owned.Open);
            await operation.WaitAsync(openTimeout,clock,token);
            if(token.IsCancellationRequested||generation!=epoch)throw new OperationCanceledException();
            endpoint=candidate;transferred=true;Ready=true;State=mode==UsbMode.Companion?"USB companion · 115200 8N1":"USB repeater · přímé místní CLI · 115200 8N1";
            Record("open","ready");_ = Task.Run(()=>Read(owned,generation,token));
        }
        catch(Exception ex)
        {
            Disconnect();Record("open","failed",ex);
            Error=Message(ex,"USB-OPEN");State="USB připojení se nezdařilo";
            throw new IOException(Error);
        }
        finally
        {
            if(!transferred&&candidate!=null)
            {
                var owned=candidate;
                if(operation is {IsCompleted:false})_ = operation.ContinueWith(t=>{_ = t.Exception;owned.Dispose();},TaskScheduler.Default);
                else {if(operation?.IsFaulted==true)_=operation.Exception;owned.Dispose();}
            }
            Connecting=false;opening.Release();Changed?.Invoke();
        }
    }
    private void Read(ISerialEndpoint owned,int generation,CancellationToken token)
    {
        var buffer=new byte[1024];
        try
        {
            while(!token.IsCancellationRequested)
            {
                int n;try {n=owned.Read(buffer);}catch(TimeoutException){continue;}
                if(n<=0)throw new IOException();var bytes=buffer[..n];
                dispatch(()=>{if(generation!=epoch||!Ready)return;try {if(Mode==UsbMode.Companion){foreach(var frame in frames.Feed(bytes))Received?.Invoke(frame);}else Bytes?.Invoke(bytes);}catch(Exception ex){Fail(ex,"USB-FRAME");}});
            }
        }
        catch(Exception ex){dispatch(()=>{if(generation==epoch&&Ready)Fail(ex,"USB-READ");});}
    }
    private void Fail(Exception ex,string code)
    {Disconnect();Record("io","failed",ex);Error=Message(ex,code);State="USB relace ukončena";Changed?.Invoke();}
    public static string Message(Exception ex,string code)=>$"{code}: "+(ex is UnauthorizedAccessException?"Port není přístupný nebo jej používá jiná aplikace. Zavřete sériový monitor; v Linuxu ověřte oprávnění skupiny dialout.":ex is TimeoutException?"Operace USB vypršela. Zkontrolujte kabel, port a režim firmwaru.":ex is OperationCanceledException?"Připojení bylo zrušeno.":"USB operace selhala. Ověřte datový kabel, zvolený port, firmware a zda zařízení neodpojilo napájení.");
    public Task WriteAsync(byte[] frame,CancellationToken cancellation=default)
    {if(Mode!=UsbMode.Companion)throw new MeshException("Binární companion příkaz nelze poslat do USB repeateru.");return WriteBytes(UsbFrameDecoder.Encode(frame),cancellation);}
    public async Task WriteBytes(byte[] bytes,CancellationToken token=default)
    {
        if(!await writing.WaitAsync(0,token))throw new MeshException("Probíhá USB zápis; další zápis nebyl zařazen.");
        int generation=epoch;
        try
        {
            var owned=endpoint;
            if(!Ready||owned==null)throw new IOException("USB není připojeno.");
            token.ThrowIfCancellationRequested();
            await Task.Run(()=>{token.ThrowIfCancellationRequested();owned.Write(bytes);},token).WaitAsync(TimeSpan.FromSeconds(5),clock,token);
            if(generation!=epoch)throw new IOException("USB relace se během zápisu změnila.");
        }
        catch(Exception ex){if(generation==epoch)Fail(ex,"USB-WRITE");throw new IOException(Message(ex,"USB-WRITE"));}
        finally {writing.Release();}
    }
    public void Disconnect()
    {
        bool wasOpen=Ready||Connecting||endpoint!=null;epoch++;Ready=false;
        lifetime?.Cancel();lifetime?.Dispose();lifetime=null;frames.Reset();
        var old=endpoint;endpoint=null;
        if(old!=null)_=Task.Run(()=>{try{old.Dispose();}catch{}});
        State="USB odpojeno";
        if(wasOpen){Record("close","closed");Closed?.Invoke();Disconnected?.Invoke();}
        Changed?.Invoke();
    }
    public void Dispose()=>Disconnect();
}
