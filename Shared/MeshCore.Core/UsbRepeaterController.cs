namespace MeshCore.Core;

/// Independent local administration: never fabricates a contact or remote admin login.
/// Only explicit advert/discovery commands use the same LoRa budget as companion service.
public sealed class UsbRepeaterController
{
    private readonly UsbRepeaterSession session;
    private readonly UsbTransport port;
    private readonly MeshSession companion;
    public event Action? Changed;
    public bool Busy {get;private set;}
    public bool Connected=>port.Ready&&port.Mode==UsbMode.Repeater;
    public bool Ready=>Connected&&!session.RequiresReconnect;
    public string Firmware {get;private set;}="";
    public string Board {get;private set;}="";
    public string Name {get;private set;}="USB repeater";
    public string Progress {get;private set;}="USB repeater odpojen";
    public string? Error {get;private set;}
    public Dictionary<string,string> Values {get;}=[];
    public List<string> Transcript {get;}=[];
    public Func<string,string,Task<bool>> Confirm {get;set;}=(_,_)=>Task.FromResult(false);
    public UsbRepeaterController(UsbTransport port,MeshSession companion)
    {
        this.port=port;this.companion=companion;session=new(port);
        port.Closed+=()=>{Values.Clear();Firmware="";Board="";Name="USB repeater";Error=null;Progress="USB odpojeno";Changed?.Invoke();};
    }
    public async Task Initialize()
    {
        Transcript.Clear();session.Reset();
        await Run(async()=>{Firmware=await Read("ver");Board=await Read("board");Name=Commands.Value(await Read("get name"));});
    }
    private async Task Run(Func<Task> action)
    {
        if(Busy)throw new MeshException("Probíhá místní USB operace; další se neřadí do fronty.");
        if(!Ready)throw new MeshException("Obnovte USB spojení a nejprve načtěte stav.");
        Busy=true;Error=null;Progress="Čekám na USB odpověď…";Changed?.Invoke();
        try{await action();Progress=Connected?"USB odpověď přijata":"USB požadavek odeslán; provedení restartu není potvrzené";}
        catch(Exception ex){Error=ex is MeshException or TimeoutException?ex.Message:UsbTransport.Message(ex,"USB-CLI");Progress="USB operace selhala";throw new MeshException(Error);}
        finally{Busy=false;Changed?.Invoke();}
    }
    private async Task<string> Read(string command)
    {
        var result=await session.Command(command);
        if(Commands.Error(result))throw new MeshException("USB firmware příkaz odmítl: "+(Commands.Sensitive(command)?"[citlivý příkaz]":result));
        return result;
    }
    public Task ReadSetting(string key)=>Run(async()=>{if(!Commands.Keys.Contains(key))throw new MeshException("Neznámé pole.");Values[key]=Commands.Value(await Read("get "+key));});
    public async Task Apply(string key,string input)
    {
        if(Busy)throw new MeshException("Probíhá USB operace.");
        var value=Commands.Validate(key,input);
        var warning=key=="radio"?" Změna může odpojit uzel od jeho LoRa sítě; některé parametry vyžadují restart.":"";
        if(!await Confirm("Zapsat nastavení přes USB?",$"set {key} {value}.{warning} Změna se ověří zpětným čtením."))return;
        await Run(async()=>{_ = await Read($"set {key} {value}");Values[key]=Commands.Value(await Read("get "+key));if(!Commands.Same(key,Values[key],value))throw new MeshException("Zápis byl odeslán, zpětné čtení ale změnu nepotvrdilo.");});
    }
    public async Task Command(string input)
    {
        var command=input.Trim();UsbRepeaterSession.Validate(command);
        if(Busy)throw new MeshException("Probíhá USB operace.");
        bool radio=command.StartsWith("advert",StringComparison.Ordinal)||command.StartsWith("discover.neighbors",StringComparison.Ordinal);
        if(!UsbRepeaterSession.ReadOnly(command)&&!await Confirm("Provést USB příkaz?",(Commands.Sensitive(command)?"Citlivý příkaz nebude uložen do historie.":command)+(radio?"\nTento příkaz aktivně vysílá přes sdílenou LoRa síť.":"\nPříkaz může změnit místní zařízení.")+(Commands.RadioWarning(command)?"\nZměna rádia může přerušit spojení s LoRa sítí.":"")))return;
        await Run(async()=>
        {
            if(radio)await companion.ReserveDirectRadio(()=>Progress="Čekám na společný limit LoRa…");
            var reply=await Read(command);
            Transcript.Add(DateTimeOffset.Now.ToString("T")+"  "+(Commands.Sensitive(command)?"[citlivý příkaz a odpověď skryty]":command+"\n"+reply));
            if(Transcript.Count>200)Transcript.RemoveAt(0);
            if(Commands.NoReply(command))port.Disconnect();
        });
    }
    public Task SyncClock()=>Command("time "+DateTimeOffset.UtcNow.ToUnixTimeSeconds());
}
