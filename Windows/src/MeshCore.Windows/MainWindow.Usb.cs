using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using MeshCore.Core;
namespace MeshCore.Windows;
public sealed partial class MainWindow
{
    private Task ConnectProfile(CompanionProfile profile)
    {
        if(profile.BluetoothAddress!=0)return Connect(profile.BluetoothAddress,profile.Account);
        MessageBox.Show(this,"Profil nemá uložené BLE zařízení. Pro USB vyberte sériový port v Připojení přes USB; pro BLE použijte skenování.","Připojení profilu",MessageBoxButton.OK,MessageBoxImage.Information);
        return Task.CompletedTask;
    }
    private void StopConnection(BleCloseReason reason=BleCloseReason.User)
    {wantedAddress=null;model.SetMonitoring(false);usb.Disconnect();ble.Disconnect(reason);}
    private async Task ConnectUsb(string port,UsbMode mode)
    {
        if(model.Busy||UsbBusy||connecting||ble.IsPairing)return;
        StopConnection();link.SelectUsb(true);usbConnecting=true;Refresh();
        try{await usb.Open(port,mode);if(mode==UsbMode.Companion)await model.Initialize(0,propagateFailure:true);else await usbRepeater.Initialize();}
        catch{usb.Disconnect();throw;}
        finally{usbConnecting=false;Navigate();}
    }
    private UIElement UsbConnectionCard()
    {
        var ports=UI.Combo(Array.Empty<string>(),260);var mode=UI.Combo(new[]{"USB companion","USB repeater – přímé CLI"},260);mode.SelectedIndex=0;
        var state=UI.Text(usb.State);var previous=refreshPage;refreshPage=()=>{previous();state.Text=usb.State+(UsbRepeater?" · "+usbRepeater.Firmware:"");};
        return UI.Group("Připojení přes USB",UI.Stack(UI.Secondary("Companion: binární protokol USB firmwaru → LoRa síť. Repeater: přímé místní CLI bez companionu a bez vzdáleného přihlášení."),
            UI.Row(mode,ports,Action("Obnovit porty",()=>{ports.ItemsSource=UsbTransport.Ports();return Task.CompletedTask;},()=>!UsbBusy)),
            UI.Row(Action("Připojit přes USB",()=>ConnectUsb(ports.SelectedItem as string??"",mode.SelectedIndex==1?UsbMode.Repeater:UsbMode.Companion),()=>!UsbBusy&&!model.Busy&&!connecting),
                Action("Odpojit USB",()=>{StopConnection();return Task.CompletedTask;},()=>usb.Ready||usbConnecting),Action("Spravovat USB repeater",()=>{navigation.SelectedIndex=3;return Task.CompletedTask;},()=>UsbRepeater&&usb.Ready)),state,
            UI.Secondary("115200 baud · 8N1 · datový USB kabel. BLE companion firmware nemusí mít USB protokol; firmware se nemění automaticky. Otevření portu může podle desky vyvolat restart. Připojení neodesílá adverty ani změny konfigurace.")),"connection");
    }
    private UIElement UsbRepeaterPage()
    {
        TextBlock state=UI.Text(""),identity=UI.Text("",20);var key=UI.Combo(Commands.Keys,240);key.SelectedIndex=0;var value=UI.Input("",260);var actual=UI.Text("Dosud nenačteno");var command=UI.Input("",320);
        var suggestions=UI.Combo(new[]{"ver","board","clock","stats-core","stats-radio","stats-packets","neighbors"}.Concat(Commands.Keys.Select(k=>"get "+k)).ToArray(),280);suggestions.SelectionChanged+=(_,_)=>{if(suggestions.SelectedItem is string text)command.Text=text;};
        var transcript=new TextBox{IsReadOnly=true,AcceptsReturn=true,TextWrapping=TextWrapping.Wrap,MinHeight=260,VerticalScrollBarVisibility=ScrollBarVisibility.Auto};
        refreshPage=()=>{identity.Text=usbRepeater.Name+" · "+usbRepeater.Firmware+" · "+usbRepeater.Board;state.Text=usbRepeater.Progress+(usbRepeater.Ready?"":" · Obnovte USB spojení před dalším příkazem.");actual.Text=usbRepeater.Values.GetValueOrDefault(key.SelectedItem as string??"","Dosud nenačteno");transcript.Text=string.Join("\n\n",usbRepeater.Transcript);};
        key.SelectionChanged+=(_,_)=>{actual.Text=usbRepeater.Values.GetValueOrDefault(key.SelectedItem as string??"","Dosud nenačteno");value.Text="";};
        bool Ready()=>usbRepeater.Ready&&!UsbBusy&&!model.Busy;
        return UI.Stack(UI.Heading("Místní správa","Repeater připojený přes USB","Čtení konfigurace a statistik nepoužívá LoRa. Advert a discovery vysílají až na výslovný potvrzený příkaz."),identity,state,
            UI.Group("Nastavení a ověření zápisu",UI.Stack(key,UI.Row(Action("Načíst hodnotu",()=>usbRepeater.ReadSetting(key.SelectedItem as string??""),Ready),actual),UI.Secondary("Nová hodnota"),value,Action("Zapsat a ověřit…",()=>usbRepeater.Apply(key.SelectedItem as string??"",value.Text),Ready))),
            UI.Group("Místní USB konzole",UI.Stack(UI.Secondary("Nápověda příkazů"),suggestions,command,UI.Row(Action("Odeslat USB příkaz…",async()=>{var text=command.Text;command.Text="";await usbRepeater.Command(text);},Ready),Action("Synchronizovat hodiny…",usbRepeater.SyncClock,Ready),Action("Restartovat…",()=>usbRepeater.Command("reboot"),Ready)),UI.Secondary("Odpovědi se párují značkou firmwaru. Po timeoutu se neprovádí opakování. Výpis je pouze v této relaci; citlivé příkazy a odpovědi se nezobrazují v historii."),transcript)),
            UI.Secondary("stats-radio: RSSI/SNR patří poslednímu paketu přijatému tímto repeaterem; noise floor je hlukové pozadí. USB spoj nemá RSSI ani SNR."));
    }
}
