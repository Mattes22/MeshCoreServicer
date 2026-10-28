using Avalonia.Controls;
using Avalonia.Layout;
using MeshCore.Core;
namespace MeshCore.Linux;
public sealed partial class MainWindow
{
    private async Task ConnectUsb(string port,UsbMode mode)
    {
        if(model.Busy||UsbBusy||ble.Connecting)return;
        StopConnection();link.SelectUsb(true);usbConnecting=true;Refresh();
        try{await usb.Open(port,mode);if(mode==UsbMode.Companion)await model.Initialize(0,propagateFailure:true);else await usbRepeater.Initialize();}
        catch{usb.Disconnect();throw;}
        finally{usbConnecting=false;ShowPage(section);}
    }
    private Control UsbConnectionCard()
    {
        var ports=new ComboBox{MinWidth=260,PlaceholderText="Vyberte sériový port"};
        var mode=new ComboBox{ItemsSource=new[]{"USB companion","USB repeater – přímé CLI"},SelectedIndex=0,MinWidth=260};
        var state=Text(usb.State);
        var previous=refreshPage;refreshPage=()=>{previous();state.Text=usb.State+(UsbRepeater?" · "+usbRepeater.Firmware:"");};
        return Card("Připojení přes USB",Text("Companion: binární protokol USB firmwaru → LoRa síť. Repeater: přímé místní CLI bez companionu a bez vzdáleného přihlášení.",14),
            Row(mode,ports,Action("Obnovit porty",()=>{ports.ItemsSource=UsbTransport.Ports();return Task.CompletedTask;},()=>!UsbBusy)),
            Row(Action("Připojit přes USB",()=>ConnectUsb(ports.SelectedItem as string??"",mode.SelectedIndex==1?UsbMode.Repeater:UsbMode.Companion),()=>!UsbBusy&&!model.Busy&&!ble.Connecting),
                Action("Odpojit USB",()=>{StopConnection();return Task.CompletedTask;},()=>usb.Ready||usbConnecting),
                Action("Spravovat USB repeater",()=>{ShowPage(3);return Task.CompletedTask;},()=>UsbRepeater&&usb.Ready)),state,
            Text("115200 baud · 8N1 · datový USB kabel. BLE companion firmware nemusí mít USB protokol; firmware se automaticky nemění. Otevření portu může podle desky vyvolat restart. Připojení neodesílá adverty ani změny konfigurace.",14));
    }
    public Control CreateUsbWorkspaceForVerification() => UsbRepeaterPage();
    private Control UsbRepeaterPage()
    {
        TextBlock state=Text("",15),identity=Text("",16,true);
        var key=new ComboBox{ItemsSource=Commands.Keys,SelectedIndex=0,MinWidth=220};var value=Input("Nová hodnota");var actual=Text("Dosud nenačteno");
        var command=Input("Např. stats-core nebo get name");
        var suggestions=new ComboBox{ItemsSource=new[]{"ver","board","clock","stats-core","stats-radio","stats-packets","neighbors"}.Concat(Commands.Keys.Select(k=>"get "+k)).ToArray(),MinWidth=260,PlaceholderText="Nápověda příkazů"};
        suggestions.SelectionChanged+=(_,_)=>{if(suggestions.SelectedItem is string text)command.Text=text;};
        var transcript=new TextBox{IsReadOnly=true,AcceptsReturn=true,TextWrapping=Avalonia.Media.TextWrapping.Wrap,MinHeight=260};
        refreshPage=()=>{identity.Text=usbRepeater.Name+" · "+usbRepeater.Firmware+" · "+usbRepeater.Board;state.Text=usbRepeater.Progress+(usbRepeater.Ready?"":" · Obnovte USB spojení před dalším příkazem.");actual.Text=usbRepeater.Values.GetValueOrDefault(key.SelectedItem as string??"","Dosud nenačteno");transcript.Text=string.Join("\n\n",usbRepeater.Transcript);};
        key.SelectionChanged+=(_,_)=>{actual.Text=usbRepeater.Values.GetValueOrDefault(key.SelectedItem as string??"","Dosud nenačteno");value.Text="";};
        bool Ready()=>usbRepeater.Ready&&!UsbBusy&&!model.Busy;
        return Stack(Text("Repeater připojený přes USB",29,true),identity,Text("Místní správa fyzicky připojeného uzlu. Čtení konfigurace a statistik nepoužívá LoRa. Advert a discovery vysílají až na výslovný potvrzený příkaz."),state,
            Card("Nastavení a ověření zápisu",key,Row(Action("Načíst hodnotu",()=>usbRepeater.ReadSetting(key.SelectedItem as string??""),Ready),actual),value,Action("Zapsat a ověřit…",()=>usbRepeater.Apply(key.SelectedItem as string??"",value.Text??""),Ready)),
            Card("Místní USB konzole",suggestions,command,Row(Action("Odeslat USB příkaz…",async()=>{var text=command.Text??"";command.Text="";await usbRepeater.Command(text);},Ready),Action("Synchronizovat hodiny…",usbRepeater.SyncClock,Ready),Action("Restartovat…",()=>usbRepeater.Command("reboot"),Ready)),Text("Odpovědi se párují značkou firmwaru. Po timeoutu se neprovádí opakování. Výpis je pouze v této relaci; citlivé příkazy a odpovědi se nezobrazují v historii.",14),transcript),
            Text("stats-radio: RSSI/SNR patří poslednímu paketu přijatému tímto repeaterem; noise floor je hlukové pozadí. USB spoj nemá RSSI ani SNR.",14),
            Action("Zpět na připojení",()=>{ShowPage(0);return Task.CompletedTask;}));
    }
}
