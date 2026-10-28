using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Templates;
using Avalonia.Data;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Platform.Storage;
using Avalonia.Styling;
using Avalonia.Threading;
using Avalonia.VisualTree;
using MeshCore.Core;
using MeshCore.Updates;
using MeshCore.Linux.DBus;
using Tmds.DBus.Protocol;

namespace MeshCore.Linux;
public sealed partial class MainWindow : Window
{
    private static string ApplicationVersion => typeof(MainWindow).Assembly.GetName().Version?.ToString(3) ?? "vývojová";
    private readonly BlueZTransport ble = new();
    private readonly Controller model;
    private readonly UsbTransport usb;
    private readonly TransportRouter link;
    private readonly UsbRepeaterController usbRepeater;
    private bool usbConnecting;
    private bool UsbRepeater => link.IsUsb && usb.Mode == UsbMode.Repeater;
    private bool UsbBusy => usbConnecting || usbRepeater.Busy;
    private readonly UpdateSession updates = new();
    private readonly ContentControl page = new();
    private readonly TextBlock connection=Text("Companion odpojen"), progress=Text("Připraveno",13), banner=Text("",14);
    private readonly StackPanel navigation = new() { Spacing=8,Width=230,Margin=new(16) };
    private readonly List<(Button Button,Func<bool> Enabled)> buttons=[];
    private readonly List<Button> navigationButtons=[];
    private Border? sidebar,header;
    private readonly DispatcherTimer timer=new() { Interval=TimeSpan.FromMilliseconds(700) };
    private Action refreshPage=()=>{};
    private int section;
    private bool exiting,updating,ticking,sleepAvailable,storageReady;
    private DateTimeOffset previousTick=DateTimeOffset.UtcNow;
    private LinuxDevice? wantedDevice;
    private string? reconnectIdentity;
    private bool reconnectAttempted;
    private int connectionIntent;
    private string? clientError;
    private DBusConnection? sessionBus,systemBus;
    private IDisposable? sleepWatch;
    private FileStream? instance;
    private readonly string dataRoot=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"MeshCoreServicer");
    private bool Local => !UsbBusy && model.Initialized && !model.Busy && !ble.Connecting && !updates.Installing;
    private bool Admin => Local && model.Admin && !model.Session.RequiresReconnect;
    public MainWindow(bool verification = false, string? localData = null)
    {
        Icon=new WindowIcon(Avalonia.Platform.AssetLoader.Open(new Uri("avares://MeshCoreServicer/Assets/AppIcon.ico")));
        Title=$"MeshCore Servicer {ApplicationVersion} · Linux";Width=1280;Height=880;MinWidth=800;MinHeight=580;FontSize=16;
        if(localData!=null)dataRoot=localData;
        usb=new(action=>Dispatcher.UIThread.Post(action));link=new(ble,usb);
        model=new(link,new SecretCredentials(),new LocalStore(dataRoot));
        usbRepeater=new(usb,model.Session);usbRepeater.Confirm=Confirm;usb.Changed+=Refresh;usbRepeater.Changed+=Refresh;
        model.Confirm=Confirm;model.Changed+=Refresh;ble.Changed+=Refresh;updates.Changed+=Refresh;
        ble.PairPrompt=PairPrompt;
        ble.Disconnected+=()=> {
            var reason=ble.ConnectionDiagnostics.Snapshot().LastOrDefault(e=>e.Stage==BleStage.Cleanup)?.CloseReason;
            if(reason==BleCloseReason.Unexpected&&model.Options.AutoReconnect&&!reconnectAttempted&&wantedDevice!=null&&!updates.Installing&&!exiting){reconnectAttempted=true;_ = ReconnectOnce(connectionIntent);}
        };
        model.NotifyMessage+=message=>_ = Notify(message);
        var root=new Grid { RowDefinitions=new("Auto,*,Auto") };
        header=new Border { Padding=new(22,16),BorderBrush=Brushes.Gray,BorderThickness=new(0,0,0,1),Child=Row(Text("MeshCore Servicer",23,true),new Border { Width=30 },connection) };
        root.Children.Add(header);
        var main=new Grid { ColumnDefinitions=new("Auto,*") };Grid.SetRow(main,1);root.Children.Add(main);
        string[] labels=["Připojení","Kontakty","Zprávy","Správa repeateru","Konzole","Diagnostika","Nastavení"];
        for(int i=0;i<labels.Length;i++) { int index=i; var button=new Button { Content=Row(NativeIcons.Icon(i),Text(labels[i])),HorizontalAlignment=HorizontalAlignment.Stretch,Padding=new(14,12),FontSize=16 };button.Click+=(_,_)=>ShowPage(index);navigation.Children.Add(button);navigationButtons.Add(button); }
        navigation.Children.Insert(0,Text("PRACOVNÍ PROSTOR",12,true));sidebar=new Border{Child=navigation};main.Children.Add(sidebar);
        var viewport=new ScrollViewer { Content=page,Padding=new(24),HorizontalScrollBarVisibility=Avalonia.Controls.Primitives.ScrollBarVisibility.Disabled };Grid.SetColumn(viewport,1);main.Children.Add(viewport);
        var statusRow=new DockPanel { LastChildFill=true };
        var applicationVersion=Text($"Verze {ApplicationVersion}",13);applicationVersion.Name="ApplicationVersion";applicationVersion.Margin=new(18,0,0,0);DockPanel.SetDock(applicationVersion,Dock.Right);statusRow.Children.Add(applicationVersion);statusRow.Children.Add(progress);
        var footer=Stack(banner,statusRow);footer.Margin=new(20,10);banner.Foreground=Brushes.DarkOrange;Grid.SetRow(footer,2);root.Children.Add(footer);Content=root;
        timer.Tick+=async(_,_)=> { var now=DateTimeOffset.UtcNow;var gap=now-previousTick;previousTick=now;if(gap>TimeSpan.FromSeconds(10)||gap<TimeSpan.Zero){model.SetMonitoring(false);StopConnection(BleCloseReason.Sleep);}if(ticking||exiting)return;ticking=true;try{if(!ble.Connecting&&!updates.Installing)await model.Tick();}catch{clientError="Pravidelné místní zpracování selhalo.";}finally{ticking=false;Refresh();if(model.Library.CheckUpdates)_ = updates.CheckIfDue(ApplicationVersion);} };
        if(!verification){Opened+=async(_,_)=>await Start();Closing+=(_,e)=>{if(!exiting){e.Cancel=true;_ = Quit();}};}
        Activated+=(_,_)=>{model.ReadingConversation=section==2;model.MarkRead();};Deactivated+=(_,_)=>model.ReadingConversation=false;
        SizeChanged+=(_,_)=>navigation.Width=Bounds.Width<1050?170:230;
        KeyDown+=(_,e)=>{if(e.Key==Key.OemComma&&e.KeyModifiers==KeyModifiers.Control){ShowPage(6);e.Handled=true;}};
        ActualThemeVariantChanged+=(_,_)=>ApplyPalette();
        ShowPage(0);
    }
    private static TextBlock Text(string text,int size=16,bool bold=false)=>new() { Text=text,FontSize=size,FontWeight=bold?FontWeight.SemiBold:FontWeight.Normal,TextWrapping=TextWrapping.Wrap };
    private static StackPanel Stack(params Control[] children) { var s=new StackPanel { Spacing=12 };foreach(var c in children)s.Children.Add(c);return s; }
    private static WrapPanel Row(params Control[] children) { var s=new WrapPanel { Orientation=Orientation.Horizontal,ItemSpacing=10,LineSpacing=10 };foreach(var c in children)s.Children.Add(c);return s; }
    private static Border Card(string title,params Control[] children)=>new() { Tag="card",Padding=new(20),Margin=new(0,0,0,16),BorderBrush=new SolidColorBrush(Color.Parse("#55808080")),BorderThickness=new(1),CornerRadius=new(14),Child=Stack([Text(title,20,true),..children]) };
    private static TextBox Input(string placeholder="",string value="")=>new() { PlaceholderText=placeholder,Text=value,MinWidth=160,Padding=new(10),FontSize=16 };
    private static CheckBox Check(string title,bool value)=>new() { Content=title,IsChecked=value };
    private Button Action(string title,Func<Task> action,Func<bool>? enabled=null)
    { var b=new Button { Content=title,Padding=new(14,9),FontSize=16,IsEnabled=storageReady&&!updates.Installing&&(enabled?.Invoke()??true) };b.Click+=async(_,_)=>await Run(action);buttons.Add((b,enabled??(()=>true)));return b; }
    private async Task ConnectSelected(LinuxDevice device)
    { if(UsbBusy)return;StopConnection();link.SelectUsb(false);connectionIntent++;wantedDevice=device;reconnectIdentity=null;reconnectAttempted=false;await ble.Connect(device,()=>model.Initialize(device.Address,propagateFailure:true));reconnectIdentity=model.Self?.Id; }
    private async Task ReconnectOnce(int intent)
    {await Task.Delay(3000);if(intent!=connectionIntent||wantedDevice is not {}device||exiting||updates.Installing||ble.Ready||ble.Connecting||model.Busy||reconnectIdentity==null)return;await Run(()=>ble.Connect(device,()=>model.Initialize(device.Address,reconnectIdentity,propagateFailure:true)));}
    private void StopConnection(BleCloseReason reason=BleCloseReason.User)
    {connectionIntent++;wantedDevice=null;model.SetMonitoring(false);usb.Disconnect();ble.Disconnect(reason);}
    private async Task Run(Func<Task> action)
    {
        if(!storageReady||updates.Installing){clientError="Místní data ještě nejsou otevřená nebo probíhá aktualizace. Operace se nespustila.";Refresh();return;}
        clientError=null;
        try { await action(); } catch(Exception ex) { clientError=BleText.Error(ex,model.Clean); }
        Refresh();
    }
    private async Task Start()
    {
        try {
            Directory.CreateDirectory(dataRoot);instance=new(Path.Combine(dataRoot,"application.lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);
            await model.Start();storageReady=true;ApplyTheme();
            try { systemBus=BlueZTransport.SystemBus();await systemBus.ConnectAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(10));sleepWatch=await new DBusService(systemBus,"org.freedesktop.login1").CreateManager("/org/freedesktop/login1").WatchPrepareForSleepAsync(sleep=>Dispatcher.UIThread.Post(()=>{if(sleep){model.SetMonitoring(false);StopConnection(BleCloseReason.Sleep);}}),emitOnCapturedContext:false);sleepAvailable=true;_ = SleepBusClosed(systemBus); } catch { clientError="Služba uspání není dostupná; plánované měření nelze spustit. Ruční správa a místní historie zůstávají dostupné."; }
            try { sessionBus=new(DBusAddress.Session!);await sessionBus.ConnectAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(10)); } catch { }
            timer.Start();Refresh();UpdateSession.MarkStartupReady();
            if(model.Library.CheckUpdates)_=updates.Check(ApplicationVersion,quiet:true);
        } catch { clientError="Aplikace už běží nebo nelze otevřít místní data. Zavřete druhou instanci a ověřte oprávnění složky aplikace.";Refresh(); }
    }
    private async Task SleepBusClosed(DBusConnection bus)
    {try{await bus.DisconnectedAsync();}catch{}Dispatcher.UIThread.Post(()=>{if(exiting)return;sleepAvailable=false;model.SetMonitoring(false);clientError="Služba uspání byla odpojena; plánované měření je zastavené.";Refresh();});}
    private async Task Quit()
    {
        if(exiting)return;
        if((model.Busy||UsbBusy)&&!await Confirm("Ukončit probíhající operaci?","Výsledek odeslaného požadavku může zůstat neověřený. Před opakováním načtěte skutečný stav."))return;
        exiting=true;timer.Stop();model.SetMonitoring(false);usb.Dispose();ble.Dispose();await model.Flush();sleepWatch?.Dispose();sessionBus?.Dispose();systemBus?.Dispose();instance?.Dispose();updates.Dispose();Close();
    }
    private async Task QuitForUpdate() { exiting=true;timer.Stop();await model.Flush();usb.Dispose();ble.Dispose();instance?.Dispose();Close(); }
    private Task BeforeUpdate() { model.SetMonitoring(false);StopConnection();return model.Flush(); }
    private void ApplyTheme() { if(Application.Current!=null)Application.Current.RequestedThemeVariant=model.Library.Theme switch {"Tmavý"=>ThemeVariant.Dark,"Světlý"=>ThemeVariant.Light,_=>ThemeVariant.Default}; }
    public void NavigateForVerification(int index) => ShowPage(index);
    private void ShowPage(int index)
    {
        section=index;buttons.Clear();refreshPage=()=>{};
        page.Content=index switch {0=>ConnectionPage(),1=>ContactsPage(),2=>MessagesPage(),3=>UsbRepeater?UsbRepeaterPage():RepeaterPage(),4=>UsbRepeater?UsbRepeaterPage():ConsolePage(),5=>DiagnosticsPage(),_=>SettingsPage()};
        model.ReadingConversation=section==2&&IsActive;model.MarkRead();Refresh();ApplyPalette();
    }
    private void ApplyPalette()
    {
        bool dark=ActualThemeVariant==ThemeVariant.Dark;
        static SolidColorBrush Brush(string value)=>new(Color.Parse(value));
        Background=Brush(dark?"#1E1E1E":"#FFFFFF");Foreground=Brush(dark?"#E3E3E3":"#252525");
        if(sidebar!=null)sidebar.Background=Brush(dark?"#1C1C1C":"#FAFAFA");
        if(header!=null)header.Background=Brush(dark?"#1C1C1C":"#FAFAFA");
        foreach(var border in this.GetVisualDescendants().OfType<Border>().Where(b=>b.Tag as string=="card")){border.Background=Background;border.BorderBrush=Brush(dark?"#333333":"#E8E8E8");}
        for(int i=0;i<navigationButtons.Count;i++){navigationButtons[i].Background=i==section?Brush(dark?"#233632":"#DFEBE9"):Brushes.Transparent;navigationButtons[i].Foreground=i==section?Brush(dark?"#59D4C2":"#056E63"):Foreground;}
    }
    private void Refresh()
    {
        if(!Dispatcher.UIThread.CheckAccess()){Dispatcher.UIThread.Post(Refresh);return;}
        connection.Text=link.IsUsb ? (UsbRepeater ? usbRepeater.Name+" · "+usb.State : (model.Self?.Name??"Companion")+" · "+usb.State) : model.Self==null?ble.State:$"{model.Self.Name} · BLE · {model.Battery/1000.0:F2} V";
        progress.Text=(UsbBusy?usbRepeater.Progress:model.Busy?model.Progress:ble.Connecting?ble.State:model.Progress)+" · "+updates.State;
        banner.Text=clientError??(link.IsUsb?usbRepeater.Error??usb.Error:ble.Error)??model.Error??model.StorageError??"";
        foreach(var (button,enabled) in buttons.ToArray())button.IsEnabled=storageReady&&!updates.Installing&&enabled();
        if(updating)return;updating=true;try{refreshPage();}finally{updating=false;}
    }
    private Control ConnectionPage()
    {
        var devices=new ListBox { Height=260 };string signature="";var details=Text("",14);var profiles=new ComboBox{ItemsSource=model.Library.Profiles.ToArray(),HorizontalAlignment=HorizontalAlignment.Stretch,ItemTemplate=new FuncDataTemplate<CompanionProfile>((p,_)=>Text(p?.Display??"Vyberte profil"))};var alias=Input("Místní přezdívka profilu");
        refreshPage=()=>{details.Text=model.Device is {}d?$"Firmware {d.Version} · build {d.Build} · companion protokol {d.Protocol} · maximální rámec {link.MaximumWriteLength} B":"Informace se načtou místně po úspěšném připojení.";var next=string.Join('|',ble.Devices);if(next==signature)return;signature=next;var old=(devices.SelectedItem as LinuxDevice)?.Path;devices.ItemsSource=ble.Devices.ToArray();devices.SelectedItem=ble.Devices.FirstOrDefault(d=>d.Path==old);};
        return Stack(Text("Připojení companionu nebo repeateru",29,true),Text("Počítač → BLE/USB companion → LoRa síť, nebo USB → místní repeater. Přímé BLE připojení k repeateru se nepoužívá."),Card("Bluetooth",Row(Action("Hledat zařízení",ble.Scan,()=>!ble.Connecting&&!model.Busy),Action("Zastavit skenování",ble.StopScan),Action("Odpojit",()=>{StopConnection();return Task.CompletedTask;},()=>ble.Ready||ble.Connecting)),devices,
            Row(Action("Systémově spárovat",()=>devices.SelectedItem is LinuxDevice d?ble.Pair(d):Task.CompletedTask,()=>!ble.Connecting&&!ble.Ready),Action("Připojit vybrané",async()=>{if(devices.SelectedItem is LinuxDevice d)await ConnectSelected(d);},()=>!ble.Connecting&&!model.Busy)),
            Text("Seznam zahrnuje kompatibilní zařízení známá BlueZ; jejich přítomnost ověří až připojení. PIN se zadává jen do systémového párování. Před připojením odpojte telefon nebo jiný BLE klient. Připojení samo neposílá LoRa diagnostiku ani konfiguraci.",14)),
            UsbConnectionCard(),Card("Informace o companionu",details),Card("Profily companionů",profiles,alias,Row(Action("Přejmenovat profil",async()=>{if(profiles.SelectedItem is CompanionProfile p)await model.RenameProfile(p,alias.Text??"");ShowPage(0);}),Action("Odstranit profil…",async()=>{if(profiles.SelectedItem is CompanionProfile p)await model.DeleteProfile(p);ShowPage(0);})),Text("Profily a preference jsou místní. K zařízení se připojuje pouze výslovným výběrem nahoře.",14)));
    }
    private Control ContactsPage()
    {
        var search=Input("Hledat název nebo veřejný klíč");var list=new ListBox { Height=450 };
        list.ItemTemplate=new FuncDataTemplate<Contact>((c,_)=>Stack(Text(c?.Name??"",18,true),Text($"{c?.Type} · {(c?.Stored==true?"uložený kontakt":"nový advert")} · {c?.Id}",12)));
        string signature="";
        void Fill(){var contacts=model.Contacts.Where(c=>c.Name.Contains(search.Text??"",StringComparison.CurrentCultureIgnoreCase)||c.Id.Contains(search.Text??"",StringComparison.OrdinalIgnoreCase)).ToArray();var next=string.Join('|',contacts.Select(c=>c.Id+c.Name+c.Stored+c.LastAdvert));if(next==signature)return;signature=next;var old=(list.SelectedItem as Contact)?.Id;list.ItemsSource=contacts;list.SelectedItem=contacts.FirstOrDefault(c=>c.Id==old);}
        search.TextChanged+=(_,_)=>Fill();refreshPage=Fill;
        return Stack(Text("Kontakty a uzly",29,true),Row(Action("Načíst kontakty",model.LoadContacts,()=>Local),Action("Objevit repeatery · LoRa",model.Discover,()=>Local)),search,list,Row(Action("Uložit kontakt",()=>list.SelectedItem is Contact c?model.StoreContact(c):Task.CompletedTask,()=>Local),Action("Spravovat repeater",async()=>{if(list.SelectedItem is Contact c&&c.Kind==2&&await model.SelectNode(c.Id))ShowPage(3);},()=>!model.Busy)),Text("Uložený kontakt ani přijatý advert neprokazují aktuální dostupnost. Ruční discovery a ping aktivně vysílají přes LoRa.",14));
    }
    private Control RepeaterPage()
    {
        var nodes=new ComboBox { HorizontalAlignment=HorizontalAlignment.Stretch };nodes.ItemTemplate=new FuncDataTemplate<Contact>((c,_)=>Text(c?.Name??"Vyberte repeater"));
        nodes.SelectionChanged+=async(_,_)=>{if(!updating&&nodes.SelectedItem is Contact c){await model.SelectNode(c.Id);ShowPage(3);}};
        var password=Input("Heslo správce");password.PasswordChar='●';var remember=Check("Uložit heslo do systémové klíčenky",false);
        var status=Text("Stav nebyl načten");var auth=Text("");var tabs=new TabControl{ItemsPanel=new FuncTemplate<Panel?>(()=>new WrapPanel())};
        Control Settings(){var fields=new StackPanel{Spacing=12};foreach(var f in model.Settings){var input=Input("Načtěte skutečnou hodnotu");input.Bind(TextBox.TextProperty,new Binding(nameof(SettingField.Draft)){Source=f,Mode=BindingMode.TwoWay});var read=Text("Nenačteno",13);read.Bind(TextBlock.TextProperty,new Binding(nameof(SettingField.Actual)){Source=f,TargetNullValue="Nenačteno"});fields.Children.Add(Card(f.Title,Text(f.Key,12),read,input,Action("Uložit a ověřit",()=>model.SaveConfig([f.Key]),()=>Admin&&f.Dirty)));}return Stack(Action("Načíst konfiguraci",()=>model.ReadConfig(),()=>Admin),Text("Rádio před zápisem vyžaduje potvrzení a může přerušit LoRa spojení. Intervaly advertu zde nejsou intervaly diagnostiky.",14),fields);}
        var overview=Stack(auth,Row(password,remember),Row(Action("Přihlásit správce",async()=>{string p=password.Text??"";password.Text="";await model.Login(p,remember.IsChecked==true);},()=>Local&&model.Node?.Stored==true),Action("Načíst uložené heslo",()=>{password.Text=model.LoadPassword()??"";return Task.CompletedTask;},()=>model.Node!=null)),Row(Action("Načíst stav jednou · LoRa",model.Ping,()=>Local&&model.Node?.Stored==true),Action("Verze a hodiny",model.ReadInfo,()=>Admin)),status);
        tabs.Items.Add(new TabItem{FontSize=16,Header="Přehled",Content=overview});tabs.Items.Add(new TabItem{FontSize=16,Header="Nastavení a rádio",Content=Settings()});
        var toolsInfo=Text("");var region=Input("Název regionu");var parent=Input("Nadřazený region");var access=Input("Veřejný klíč uživatele");var role=Input("Oprávnění 0–3","0");var newPassword=Input("Nové heslo");newPassword.PasswordChar='●';var savePassword=Check("Uložit nové heslo správce",false);
        var tools=Stack(Row(Action("Telemetrie",model.ReadTelemetry,()=>Admin),Action("Sousedi",model.ReadNeighbours,()=>Admin),Action("Regiony",model.ReadRegions,()=>Admin),Action("ACL",model.ReadAccess,()=>Admin)),toolsInfo,Card("Regiony",region,parent,Row(Action("Přidat region",()=>model.ChangeRegion("put",region.Text??"",parent.Text??""),()=>Admin),Action("Odebrat region",()=>model.ChangeRegion("remove",region.Text??"",""),()=>Admin))),Card("Řízení přístupu",access,role,Action("Změnit oprávnění",()=>model.ChangeAccess(access.Text??"",byte.Parse(role.Text??"")),()=>Admin)),Card("Změna hesla",newPassword,savePassword,Row(Action("Změnit heslo správce…",async()=>{string p=newPassword.Text??"";newPassword.Text="";await model.ChangePassword(p,false,savePassword.IsChecked==true);},()=>Admin),Action("Změnit heslo hosta…",async()=>{string p=newPassword.Text??"";newPassword.Text="";await model.ChangePassword(p,true,false);},()=>Admin))),Row(Action("Synchronizovat hodiny…",model.SyncClock,()=>Admin),Action("Flood advert…",()=>model.Advert(false),()=>Admin),Action("Restartovat…",model.Restart,()=>Admin)),Text("Hesla správce/hosta, identitní klíče a další pokročilé příkazy lze spravovat také v konzoli. Citlivé příkazy se neukládají do historie ani diagnostického exportu.",14));
        tabs.Items.Add(new TabItem{FontSize=16,Header="Nástroje",Content=tools});
        var cz=Check("Použít volitelnou předvolbu české komunity",false);var owner=Input("Veřejný kontakt na vlastníka · volitelné");var setup=Text("");
        tabs.Items.Add(new TabItem{FontSize=16,Header="Prvotní nastavení",Content=Stack(cz,Text("Flood advert 25 h, zero-hop 0, dutycycle 10 % / af 9, 2B hashe cest. Pouze návrh ke kontrole; nic se automaticky nezapíše.",14),owner,Action("Načíst stav a připravit návrhy",()=>model.PrepareSetup(cz.IsChecked==true,owner.Text??""),()=>Admin),setup)});
        var snapshots=new ComboBox { HorizontalAlignment=HorizontalAlignment.Stretch };var snapshotName=Input("Název snímku");
        tabs.Items.Add(new TabItem{FontSize=16,Header="Historie a měření",Content=Stack(DiagnosticMeasurementPanel(),Card("Snímky konfigurace",snapshotName,Action("Uložit načtené hodnoty",()=>{model.CaptureSnapshot(snapshotName.Text??"");return Task.CompletedTask;},()=>Local),snapshots,Row(Action("Exportovat snímek",async()=>{if(snapshots.SelectedItem is ConfigSnapshot snapshot)await Save("MeshCore-snímek.json",System.Text.Json.JsonSerializer.Serialize(snapshot,LocalStore.Json));}),Action("Importovat snímek",async()=>{var text=await OpenJson();if(text!=null)model.ImportSnapshot(text);}),Action("Obnovit vybrané hodnoty…",async()=>{if(snapshots.SelectedItem is ConfigSnapshot snapshot)await model.Restore(snapshot,snapshot.Values.Keys.Where(k=>k!="radio").ToArray());},()=>Admin)),Text("Obnova vyžaduje potvrzení a živé porovnání. Rádio je z automatického výběru vynechané.",14)))});
        var healthRefresh=refreshPage;
        refreshPage=()=>{
            healthRefresh();var repeaters=model.Contacts.Where(c=>c.Kind==2).ToArray();if(nodes.ItemsSource is not Contact[] old||!old.SequenceEqual(repeaters)){nodes.ItemsSource=repeaters;nodes.SelectedItem=model.Node;}
            auth.Text=model.Node==null?"Vyberte uložený repeater.":model.Node.Name+" · "+(model.Admin?"správce ověřen":"bez přihlášení");
            status.Text=model.Status is { } s?$"Odpověď {model.StatusRead?.LocalDateTime:g}\nBaterie {s.Battery/1000.0:F3} V · uptime {s.Uptime} s · RX {s.Received} · TX {s.Sent}\nPoslední paket přijatý repeaterem: RSSI {s.LastRssi} dBm · SNR {s.LastSnr:F2} dB\nNoise floor {s.Noise} dBm je šum, nikoli síla signálu.\n{model.Firmware}\n{model.Clock}":"Stav nebyl načten; uložení kontaktu nedokládá dostupnost.";
            toolsInfo.Text=$"{model.TelemetryText}\n{model.RegionText}\n"+string.Join('\n',model.Neighbours)+"\n"+string.Join('\n',model.Access);
            setup.Text=model.SetupSummary+"\n"+string.Join('\n',model.SetupSteps.Select(s=>s.Command+" · "+s.State));var selected=(snapshots.SelectedItem as ConfigSnapshot)?.Id;snapshots.ItemsSource=model.Operations.Snapshots.ToArray();snapshots.SelectedItem=model.Operations.Snapshots.FirstOrDefault(s=>s.Id==selected);
        };
        return Stack(Text("Vzdálená správa přes LoRa",29,true),nodes,tabs);
    }
    private Control DiagnosticMeasurementPanel()
    {
        var hours=Input("Interval v hodinách",DiagnosticPlan.HoursInput(model.Options.DiagnosticMinutes));var count=Input("Počet vzorků",model.Options.DiagnosticSamples.ToString());
        var plan=Text("",14);var state=Text("",14);var samples=Text("",13);var bar=new ProgressBar{Minimum=0,Maximum=6,Height=7};var chart=new BatteryChart();
        void Preview(){try{var p=new DiagnosticPlan(DiagnosticPlan.MinutesFromHours(hours.Text??""),int.Parse(count.Text??""),model.MeasurementRoute);plan.Text=$"{p.Samples} požadavků a očekávaných odpovědí · délka {DiagnosticPlan.HoursText(p.DurationMinutes)} · první po {DiagnosticPlan.HoursText(p.IntervalMinutes)}";}catch{plan.Text="Zvolte 3–24 hodin, 1–6 vzorků a celkem nejvýše 24 hodin.";}}
        hours.TextChanged+=(_,_)=>Preview();count.TextChanged+=(_,_)=>Preview();Preview();
        refreshPage=()=>{hours.IsEnabled=count.IsEnabled=!model.Monitoring&&!model.Busy;var m=model.Measurement;bar.Maximum=m?.Plan.Samples??6;bar.Value=m?.Consumed??0;state.Text=m==null?"Měření je vypnuté.":$"{(m.Running?"Probíhá":"Ukončeno")} · termíny {m.Consumed}/{m.Plan.Samples} · uloženo {m.Received} · přeskočeno {m.Skipped} · zbývá {m.Remaining}"+(m.Next is {}next?$" · příští {next.LocalDateTime:g}":"");chart.Samples=model.Operations.Samples.TakeLast(80).ToArray();chart.InvalidateVisual();samples.Text=string.Join('\n',model.Operations.Samples.TakeLast(12).Reverse().Select(s=>$"{s.Date.LocalDateTime:g} · {s.Status.Battery} mV · uptime {s.Status.Uptime} s · RX {s.Status.Received} · TX {s.Status.Sent}"));};
        return Card("Časově omezené diagnostické měření",Row(Text("Interval · hodiny"),hours,Text("Vzorky"),count),plan,Text("Každý vzorek aktivně vyšle požadavek přes sdílenou LoRa síť a vyvolá odpověď. Výchozí plán: 3 vzorky po 4 h, první po 4 h a poslední po 12 h. Žádný interval není univerzálně bezpečný.",14),Row(Action("Spustit měření",async()=>{await model.SetDiagnosticOptions(DiagnosticPlan.MinutesFromHours(hours.Text??""),int.Parse(count.Text??""));model.SetMonitoring(true);},()=>Admin&&sleepAvailable&&!model.Monitoring),Action("Zastavit",()=>{model.SetMonitoring(false);return Task.CompletedTask;},()=>model.Monitoring)),bar,state,Text("Ruční servis a měření sdílí 60 požadavků/h, z toho 12 bez známé trasy; prodlevy 15/60 s. Žádný retry, dohánění ani obnovení po spánku. Graf a historie jsou pouze místní.",14),chart,samples);
    }
    private Control MessagesPage()
    {
        var conversations=new ComboBox{HorizontalAlignment=HorizontalAlignment.Stretch};var messages=Input();messages.IsReadOnly=true;messages.AcceptsReturn=true;messages.Height=350;
        var draft=Input("Napsat zprávu");draft.AcceptsReturn=true;draft.Height=90;string signature="";
        conversations.SelectionChanged+=(_,_)=>{if(!updating&&conversations.SelectedItem is ConversationItem item)model.SelectConversation(item.Id);};
        refreshPage=()=>{var available=model.Conversations.Select(c=>new ConversationItem(c.Id,c.Title)).ToArray();var next=string.Join('|',available.Select(c=>c.Id+c.Title));if(next!=signature){signature=next;conversations.ItemsSource=available;conversations.SelectedItem=available.FirstOrDefault(c=>c.Id==model.Conversation);}messages.Text=string.Join("\n\n",model.Messages.TakeLast(200).Select(m=>m.Display));};
        return Stack(Text("Zprávy",29,true),conversations,Row(Action("Načíst kanály a frontu · BLE",model.RefreshMessages,()=>Local),Action("Ztišit / obnovit oznámení",()=>model.Mute(!model.Muted),()=>model.Conversation!=null)),messages,draft,Action("Odeslat",async()=>{await model.SendMessage(draft.Text??"");if(model.Error==null)draft.Text="";},()=>Local&&model.Conversation!=null),Text("Počet zachycených přeposlání znamená skutečně přijaté rádiové kopie, nikoli unikátní uzly nebo potvrzení doručení kanálu.",14));
    }
    private sealed record ConversationItem(string Id,string Title){public override string ToString()=>Title;}
    private Control ConsolePage()
    {
        var command=Input("Vzdálený CLI příkaz");var help=Text("",14);var output=Input();output.IsReadOnly=true;output.AcceptsReturn=true;output.Height=350;
        int historyIndex=-1;string savedDraft="";var suggest=new ListBox{Height=150};command.TextChanged+=(_,_)=>{suggest.ItemsSource=model.Options.Suggestions?Commands.Suggest(command.Text??"",model.History,model.Options.SuggestWrites,model.Options.History).Take(8).ToArray():Array.Empty<string>();help.Text=Commands.Entry(command.Text??"")?.Detail??"Příkaz se odešle až po výslovném odeslání. Tab pouze doplní návrh.";};
        suggest.DoubleTapped+=(_,_)=>{if(suggest.SelectedItem is string text)command.Text=text;};
        command.KeyDown+=async(_,e)=>{if(e.Key==Key.Escape){suggest.SelectedItem=null;e.Handled=true;}else if(e.Key is Key.Up or Key.Down){if(historyIndex<0)savedDraft=command.Text??"";historyIndex=Math.Clamp(historyIndex+(e.Key==Key.Up?1:-1),-1,Math.Max(-1,model.History.Count-1));command.Text=historyIndex<0?savedDraft:model.History.AsEnumerable().Reverse().ElementAt(historyIndex);command.CaretIndex=command.Text?.Length??0;e.Handled=true;}else if(e.Key==Key.Tab&&suggest.Items.Count>0){command.Text=suggest.SelectedItem as string??suggest.Items[0] as string;e.Handled=true;}else if(e.Key==Key.Enter&&(model.Options.EnterSends||e.KeyModifiers.HasFlag(KeyModifiers.Control))){e.Handled=true;await Run(()=>model.SendCli(command.Text??""));}};
        refreshPage=()=>output.Text=string.Join("\n\n",model.Console.TakeLast(100).Select(l=>$"{l.Date.LocalDateTime:T} > {l.Command}\n{l.Response}\n{l.State}"));
        return Stack(Text("Vzdálená konzole",29,true),Text("Příkazy pro repeater jdou po LoRa přes companion. Zpracování je sekvenční a sdílí servisní rozpočet.",14),command,suggest,help,Action("Odeslat příkaz…",()=>model.SendCli(command.Text??""),()=>Admin),output);
    }
    private Control DiagnosticsPage()
    {
        var log=Input();log.IsReadOnly=true;log.AcceptsReturn=true;log.Height=460;
        refreshPage=()=>log.Text=string.Join('\n',model.Log.TakeLast(100).Select(l=>$"{l.Date.LocalDateTime:T} · {l.Category}").Concat(ble.ConnectionDiagnostics.Snapshot().TakeLast(100).Select(e=>$"{e.Date.LocalDateTime:T} · {BleText.Stage(e.Stage)} · {e.Outcome} {e.Failure?.Id}")));
        return Stack(Text("Diagnostika",29,true),Row(Action("Export připojení BLE/USB bez identit…",()=>Save("MeshCore-BLE-diagnostika.json",model.BleDiagnosticReport())),Action("Export diagnostiky…",()=>Save("MeshCore-diagnostika.json",model.DiagnosticReport()))),Text("Export je dostupný i bez úspěšného připojení. Neobsahuje MAC, PINy, hesla, privátní klíče ani obsah komunikace.",14),log);
    }
    private Control SettingsPage()
    {
        var theme=new ComboBox{ItemsSource=new[]{"Systém","Světlý","Tmavý"},SelectedItem=model.Library.Theme};var auto=Check("Automaticky zjišťovat nové verze",model.Library.CheckUpdates);var reconnect=Check("Jeden pokus o obnovu neočekávaně ztraceného BLE spoje",model.Options.AutoReconnect);var sound=Check("Zvuk oznámení",model.Library.Sound);var notifications=Check("Systémová oznámení nových zpráv",model.Library.Notifications);var preview=Check("Zobrazit obsah zprávy v oznámení",model.Library.NotificationText);var suggest=Check("Nápověda a doplňování konzole",model.Options.Suggestions);var writes=Check("Nabízet i příkazy měnící konfiguraci",model.Options.SuggestWrites);var enter=Check("Enter odešle CLI příkaz",model.Options.EnterSends);
        return Stack(Text("Nastavení aplikace",29,true),Card("O aplikaci",Text($"Verze {ApplicationVersion}",18,true),Text($"Ubuntu/Debian {UpdateSession.Platform[6..]}",14)),Card("Vzhled a oznámení",theme,notifications,preview,sound,reconnect,Text("Po chybě obnovy pokračujte ručně. Po uspání, restartu nebo aktualizaci se připojení, měření ani správce neobnovují.",14)),Card("Konzole",suggest,writes,enter),Card("Aktualizace",auto,Text("Kontrola stáhne pouze podepsanou informaci z vlastního serveru. Teprve po potvrzení se stáhnou změněné soubory a aplikace se restartuje. Původní verze zůstane pro návrat při chybě. Přihlášení správce ani měření se neobnoví.",14),Row(Action("Zkontrolovat aktualizace",()=>updates.Check(ApplicationVersion),()=>!updates.Checking&&!updates.Installing),Action("Aktualizovat a restartovat…",()=>updates.Install(Confirm,()=>!model.Busy&&!ble.Connecting&&!UsbBusy,BeforeUpdate,QuitForUpdate),()=>updates.Plan!=null&&!updates.Installing))),Action("Uložit nastavení",async()=>{model.Library.Theme=theme.SelectedItem as string??"Systém";model.Library.CheckUpdates=auto.IsChecked==true;model.Options.AutoReconnect=reconnect.IsChecked==true;model.Library.Sound=sound.IsChecked==true;model.Library.Notifications=notifications.IsChecked==true;model.Library.NotificationText=preview.IsChecked==true;model.Options.Suggestions=suggest.IsChecked==true;model.Options.SuggestWrites=writes.IsChecked==true;model.Options.EnterSends=enter.IsChecked==true;await model.SaveLibrary();ApplyTheme();}),Text($"Verze {ApplicationVersion} · Ubuntu/Debian {UpdateSession.Platform[6..]} · BlueZ + systémová klíčenka Secret Service",13),Action("Ukončit aplikaci",Quit));
    }
    private async Task<bool> Confirm(string title,string message)
    {
        var dialog=new Window{Title=title,Width=580,Height=300,WindowStartupLocation=WindowStartupLocation.CenterOwner,CanResize=false};var yes=new Button{Content="Potvrdit",Padding=new(14,9)};var no=new Button{Content="Zrušit",Padding=new(14,9)};yes.Click+=(_,_)=>dialog.Close(true);no.Click+=(_,_)=>dialog.Close(false);dialog.Content=new Border{Padding=new(24),Child=Stack(Text(message),Row(no,yes))};return await dialog.ShowDialog<bool>(this);
    }
    private async Task<string?> PairPrompt(string title,string? pin)
    {
        if(!Dispatcher.UIThread.CheckAccess())return await Dispatcher.UIThread.InvokeAsync(()=>PairPrompt(title,pin));
        if(pin!=null)return await Confirm(title,pin.Length>0?"PIN: "+pin:"Potvrďte operaci pro vlastní zařízení.")?"ano":null;
        var input=Input("PIN z vlastního zařízení");input.PasswordChar='●';var dialog=new Window{Title=title,Width=460,Height=240,WindowStartupLocation=WindowStartupLocation.CenterOwner};var ok=new Button{Content="Potvrdit"};var cancel=new Button{Content="Zrušit"};ok.Click+=(_,_)=>dialog.Close(input.Text);cancel.Click+=(_,_)=>dialog.Close(null);dialog.Content=new Border{Padding=new(22),Child=Stack(Text("PIN se nepíše do logu ani neukládá."),input,Row(cancel,ok))};var result=await dialog.ShowDialog<string?>(this);input.Text="";return result;
    }
    private async Task Save(string name,string text)
    {
        var file=await StorageProvider.SaveFilePickerAsync(new(){Title="Uložit redigovaný export",SuggestedFileName=name});if(file==null)return;await using var stream=await file.OpenWriteAsync();stream.SetLength(0);await using var writer=new StreamWriter(stream);await writer.WriteAsync(text);
    }
    private async Task<string?> OpenJson()
    {
        var files=await StorageProvider.OpenFilePickerAsync(new(){Title="Importovat místní snímek",AllowMultiple=false});if(files.Count==0)return null;await using var stream=await files[0].OpenReadAsync();if(stream.Length>1_000_000)throw new MeshException("Snímek je příliš velký.");using var reader=new StreamReader(stream);return await reader.ReadToEndAsync();
    }
    private async Task Notify(ChatRecord message)
    {
        if(sessionBus==null)return;
        try{string summary=model.Library.NotificationText?message.Title:"MeshCore Servicer",body=model.Library.NotificationText?message.Sender+": "+message.Text:"Přišla nová zpráva.";await new DBusService(sessionBus,"org.freedesktop.Notifications").CreateNotifications("/org/freedesktop/Notifications").NotifyAsync("MeshCore Servicer",0,"",System.Security.SecurityElement.Escape(summary)??"",System.Security.SecurityElement.Escape(body)??"",[],new(){["suppress-sound"]=!model.Library.Sound},5000);}catch{}
    }
}
internal sealed class BatteryChart : Control
{
    public HealthSample[] Samples { get; set; }=[];
    public BatteryChart(){Height=170;MinWidth=250;}
    public override void Render(DrawingContext context)
    {
        base.Render(context);if(Samples.Length<2)return;
        double min=Samples.Min(s=>s.Status.Battery)-1,max=Samples.Max(s=>s.Status.Battery)+1;var start=Samples[0].Date;double seconds=Math.Max(1,(Samples[^1].Date-start).TotalSeconds);var pen=new Pen(Brushes.Teal,2);Point? previous=null;
        foreach(var s in Samples){var point=new Point(8+(s.Date-start).TotalSeconds/seconds*Math.Max(1,Bounds.Width-16),8+(max-s.Status.Battery)/(max-min)*Math.Max(1,Bounds.Height-16));if(previous is {}p)context.DrawLine(pen,p,point);previous=point;}
    }
}
