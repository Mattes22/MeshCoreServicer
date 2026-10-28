using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using MeshCore.Core;
using Microsoft.Win32;

namespace MeshCore.Windows;
public sealed partial class MainWindow
{
    private UIElement RepeaterPage()
    {
        var nodes = UI.Combo(model.Contacts.Where(c => c.Kind == 2).ToArray(), 210); nodes.SelectedItem = model.Node; bool updating = false;
        nodes.SelectionChanged += async (_, _) => { if (!updating && nodes.SelectedItem is Contact c) await Invoke(async () => { await model.SelectNode(c.Id); }); };
        var heading = UI.Heading("Vzdálená správa přes LoRa", "Správa repeateru", "Vyberte uzel, ověřte přístup a načtěte jeho stav.", nodes);
        var auth = UI.Text("Bez přihlášení", 11); var stored = UI.Pill("Uložený kontakt"); var authPill = UI.Pill("Bez přihlášení"); authPill.Child = auth; var verified = UI.Secondary("Dostupnost neověřená", 11); var key = UI.Secondary("", 11); key.FontFamily = UI.Mono;
        var newNode = UI.Group("Kontakt ještě není uložený", UI.Stack(UI.Secondary("Před vzdálenou správou jej výslovně uložte do companionu."), Action("Uložit do companionu", () => model.Node is { } c ? model.StoreContact(c) : Task.CompletedTask, () => Local && model.Node?.Stored == false)), "contacts");
        var noNode = UI.Group("Vyberte repeater z kontaktů", UI.Stack(UI.Empty("repeater", "Začněte výběrem uzlu", "Nejprve připojte companion a načtěte jeho kontakty. Vzdálený repeater se spravuje po LoRa."), UI.Primary(Action("Otevřít kontakty", () => { navigation.SelectedIndex = 1; return Task.CompletedTask; }))), "repeater");
        var pendingBanner = UI.Banner("Doporučená kontrola stavu", "V historii je restart nebo neověřená změna. Dostupnost a hodiny ověřte před opakováním zápisu.", true);
        var battery = new Metric("Baterie repeateru", "battery", "Skutečné napětí · bez odhadu procent").Initialize(); var uptime = new Metric("Doba běhu", "clock", "Od posledního restartu").Initialize(); var rx = new Metric("Přijaté pakety", "down").Initialize(); var tx = new Metric("Odeslané pakety", "up").Initialize(); var metrics = UI.Columns(battery.View, uptime.View, rx.View, tx.View);
        var radioInfo = UI.ReadText("Stav zatím nebyl načtený.", 170); radioInfo.Background = Brushes.Transparent; radioInfo.BorderThickness = new(0); var trafficInfo = UI.ReadText("Stav zatím nebyl načtený.", 170); trafficInfo.Background = Brushes.Transparent; trafficInfo.BorderThickness = new(0); var firmwareInfo = UI.ReadText("Nenačteno", 90); firmwareInfo.Background = Brushes.Transparent; firmwareInfo.BorderThickness = new(0);
        PasswordBox password = new() { MinWidth = 230, Padding = new(10, 7, 10, 7), Margin = new(0, 0, 8, 8) }; var remember = UI.Check("Po ověření uložit heslo do systémového úložiště Windows");
        async Task Login() { var secret = password.Password; password.Clear(); await model.Login(secret, remember.IsChecked == true); }
        password.KeyDown += async (_, e) => { if (e.Key == System.Windows.Input.Key.Enter && Local && model.Node?.Stored == true) await Invoke(Login); };
        var login = UI.Group("Přístup správce", UI.Stack(UI.Row(password, Action("Z úložiště", () => { password.Password = model.LoadPassword() ?? ""; return Task.CompletedTask; }, () => !model.Busy && model.Node != null), UI.Primary(Action("Přihlásit správce", Login, () => Local && model.Node?.Stored == true))), remember), "lock", "Přihlášení k vybranému repeateru přes companion a LoRa.");
        var tabs = new TabControl(); void Tab(string title, UIElement content) => tabs.Items.Add(new TabItem { Header = title, Content = content });
        var sampleTable = UI.Table(("Čas", "Date"), ("Baterie (mV)", "Status.Battery"), ("Uptime (s)", "Status.Uptime"), ("RX", "Status.Received"), ("TX", "Status.Sent"));
        var graph = new System.Windows.Shapes.Polyline { StrokeThickness = 2 }; graph.SetResourceReference(System.Windows.Shapes.Shape.StrokeProperty, "Accent"); Canvas chart = new() { Height = 110, ClipToBounds = true, Background = Brushes.Transparent }; chart.Children.Add(graph);
        void Plot() { var values = model.Operations.Samples.TakeLast(80).Select(s => (double)s.Status.Battery).ToArray(); PointCollection points = new(); if (values.Length > 1) { var lo = values.Min(); var range = Math.Max(50, values.Max() - lo); for (int i = 0; i < values.Length; i++) points.Add(new(i * Math.Max(100, chart.ActualWidth) / (values.Length - 1), 95 - (values[i] - lo) / range * 80)); } graph.Points = points; }
        chart.SizeChanged += (_, _) => Plot();
        var pending = UI.ReadText("", 140); var telemetry = UI.ReadText("", 160); var regions = UI.ReadText("", 160);
        var neighbours = UI.Table(("Veřejný klíč", "Key"), ("Slyšen před (s)", "SecondsAgo"), ("SNR na repeateru (dB)", "Snr")); var acl = UI.Table(("Prefix veřejného klíče", "Prefix"), ("Role", "Role"), ("Byte oprávnění", "Permissions"));
        var snapshots = UI.Combo(Array.Empty<ConfigSnapshot>(), 330); var snapshotName = UI.Input("", 180); var regionOp = UI.Combo(new[] { "put", "remove", "allowf", "denyf", "home", "default" }, 100); regionOp.SelectedIndex = 0; var regionName = UI.Input("", 130); var regionParent = UI.Input("", 130); var accessKey = UI.Input("", 330); var accessRole = UI.Combo(new[] { "0 · Odebrat", "1 · Čtení", "2 · Zápis", "3 · Správce" }, 140); accessRole.SelectedIndex = 1;
        var setupStatus = UI.Secondary(model.SetupSummary); var setupReads = UI.ReadText("", 180); setupReads.FontFamily = UI.Mono;
        var cz = UI.Check("Použít volitelný profil české komunity"); var owner = UI.Input("", 280); string? toolsNode = model.SelectedNode;
        var editors = new List<(SettingField Field, TextBox Editor, TextBlock Status)>();
        var dirtyLabel = UI.Text("", 13); dirtyLabel.FontWeight = FontWeights.SemiBold; var save = UI.Primary(Action("Zkontrolovat a uložit", () => model.SaveConfig(), () => Admin && model.Settings.Any(f => f.Dirty)));
        var dirtyBar = UI.Card(UI.Columns(UI.Stack(dirtyLabel, UI.Secondary("Změny se odešlou až po uložení.", 10)), UI.Row(Action("Zahodit úpravy", () => { foreach (var f in model.Settings) f.Draft = f.Actual ?? ""; return Task.CompletedTask; }, () => !model.Busy), save)), 14); dirtyBar.Margin = new(0, 12, 0, 0); dirtyBar.SetResourceReference(Border.BackgroundProperty, "SubtleSurface");
        void UpdateDirty() { int count = model.Settings.Count(f => f.Dirty); dirtyLabel.Text = $"{count} neuložené hodnoty"; dirtyBar.Visibility = count == 0 ? Visibility.Collapsed : Visibility.Visible; save.IsEnabled = Admin && count > 0; navigationCounts[3].Text = count > 0 ? "●" : ""; }
        UIElement Editor(string fieldKey, string title, string hint)
        {
            var field = model.Settings.Single(f => f.Key == fieldKey); var input = UI.Input(field.Draft, 160); input.MaxWidth = 480; input.HorizontalAlignment = HorizontalAlignment.Stretch; var state = UI.Secondary("Nenačteno", 10); var label = UI.Text(title); label.FontWeight = FontWeights.Medium;
            var row = UI.Columns(UI.Stack(label, UI.Secondary(hint, 11)), UI.Stack(input, state)); row.Margin = new(0, 4, 0, 12); input.TextChanged += (_, _) => { if (!updating) { field.Draft = input.Text; UpdateDirty(); } }; editors.Add((field, input, state)); return row;
        }
        var radioField = model.Settings.Single(f => f.Key == "radio"); var radioValues = Enumerable.Range(0, 4).Select(_ => UI.Input("", 70)).ToArray();
        foreach (var part in radioValues) part.TextChanged += (_, _) => { if (!updating) { radioField.Draft = string.Join(',', radioValues.Select(p => p.Text.Trim())); UpdateDirty(); } };
        var radioStatus = UI.Secondary("Nenačteno", 11);
        var radioFields = UI.Columns(UI.Stack(UI.Secondary("Frekvence · MHz"), radioValues[0]), UI.Stack(UI.Secondary("Šířka pásma · kHz"), radioValues[1]), UI.Stack(UI.Secondary("Spreading factor"), radioValues[2]), UI.Stack(UI.Secondary("Coding rate · CR"), radioValues[3]));
        Tab("Přehled", UI.Stack(login, UI.Columns(UI.Stack(UI.Text("Provozní přehled", 15), UI.Secondary("Snímek ze skutečné odpovědi repeateru")), UI.WithIcon(Action("Ověřit a načíst stav", () => model.Ping(), () => Local && model.Node?.Stored == true), "refresh")), metrics,
            UI.Columns(UI.Group("Rádiový příjem repeateru", radioInfo, "diagnostics", "Poslední paket na rádiu repeateru; odesílatel není známý."), UI.Group("Provoz a vysílací čas", trafficInfo, "diagnostics")),
            UI.Group("Firmware a hodiny", UI.Stack(firmwareInfo, UI.Row(Action("Načíst verzi a hodiny", () => model.ReadInfo(), () => Admin), Action("Synchronizovat hodiny…", () => model.SyncClock(), () => Admin))), "chip"),
            UI.Group("Nástroje repeateru", UI.Stack(UI.Row(Action("Odeslat advert", () => model.Advert(false), () => Admin), Action("Otevřít konzoli", () => { navigation.SelectedIndex = 4; return Task.CompletedTask; }), Action("Restartovat…", () => model.Restart(), () => Admin)), UI.Secondary("Vysílání je ruční. Restart vyžaduje potvrzení a firmware na něj neposílá odpověď.")), "tools")));
        Tab("Nastavení", UI.Stack(UI.Row(Action("Načíst nastavení", () => model.ReadConfig(Commands.BasicKeys.Where(k => k is not ("radio" or "tx"))), () => Admin)),
            UI.Group("Identita a poloha", UI.Stack(Editor("name", "Název", "Nejvýše 23 UTF-8 bajtů"), UI.Divider(), Editor("lat", "Zeměpisná šířka", "−90 až 90 · desetinná tečka"), UI.Divider(), Editor("lon", "Zeměpisná délka", "−180 až 180 · desetinná tečka")), "contacts", "Hodnoty se načítají z repeateru; nepřebírají se automaticky z kontaktu."),
            UI.Group("Přeposílání paketů", Editor("repeat", "Funkce repeateru", "on = zapnout · off = vypnout"), "repeater", "Změna se odešle až po stisknutí Uložit."),
            UI.Group("Informace o vlastníkovi", Editor("owner.info", "Veřejný kontakt", "Nejvýše 118 UTF-8 bajtů"), "contacts", "Veřejné kontaktní údaje správce. Znak | firmware převádí na nový řádek."),
            UI.Group("Intervaly advertů", UI.Stack(Editor("advert.interval", "Zero-hop advert", "0 nebo sudé 60–240 minut"), UI.Divider(), Editor("flood.advert.interval", "Flood advert", "0 nebo 3–168 hodin")), "clock", "Hodnota 0 vypíná periodický advert. Přeposílání se nastavuje samostatně.")));
        Tab("Rádio", UI.Stack(UI.Banner("Změna rádia může přerušit LoRa spojení", "Uložené parametry se použijí po restartu. Před změnou ověřte odpovídající nastavení companionu a repeateru.", true),
            UI.Row(Action("Načíst rádio a síťové parametry", () => model.ReadConfig(["radio", "tx", "dutycycle", "af", "path.hash.mode", "flood.max", "flood.max.advert", "flood.max.unscoped", "loop.detect"]), () => Admin)),
            UI.Group("Parametry rádia", UI.Stack(radioFields, radioStatus, UI.Divider(), Editor("tx", "Vysílací výkon", "1–22 dBm · podle možností zařízení")), "repeater", "Pracujte s reálně načtenými hodnotami své sítě."),
            UI.Group("Síťové parametry", UI.Stack(Editor("dutycycle", "Duty cycle", "1–100 %"), Editor("af", "Airtime factor", "0–9 · alternativa ke stejnému poli dutycycle"), Editor("path.hash.mode", "Hash cesty", "0 = 1 B · 1 = 2 B · 2 = 3 B"), Editor("flood.max", "Limit flood", "0–64"), Editor("flood.max.advert", "Limit flood advertu", "0–64"), Editor("flood.max.unscoped", "Limit flood mimo regiony", "0–64"), Editor("loop.detect", "Detekce smyček", "off, minimal, moderate, strict")), "settings", "Dutycycle a af mění stejné pole; upravujte vždy pouze jednu hodnotu.")));
        var tools = new TabControl(); void Tool(string title, UIElement content) => tools.Items.Add(new TabItem { Header = title, Content = content });
        Tool("Diagnostika", UI.Stack(UI.Group("Telemetrie", UI.Stack(Action("Načíst telemetrii", () => model.ReadTelemetry(), () => Admin), telemetry), "diagnostics"), UI.Group("Sousedi bez přeskoku", UI.Stack(Action("Načíst sousedy", () => model.ReadNeighbours(), () => Admin), UI.Secondary("SNR se vztahuje k poslednímu paketu souseda přijatému repeaterem."), neighbours), "repeater")));
        Tool("Přístup a hesla", UI.Stack(UI.Group("Řízení přístupu", UI.Stack(Action("Načíst ACL", () => model.ReadAccess(), () => Admin), UI.Secondary("Odpověď obsahuje šestibajtové prefixy a může být oříznutá. Pro změnu je vyžadován celý veřejný klíč."), acl, accessKey, UI.Row(accessRole, Action("Změnit oprávnění…", () => model.ChangeAccess(accessKey.Text.Trim(), (byte)accessRole.SelectedIndex), () => Admin))), "lock"), UI.Group("Hesla vzdálené správy", UI.Row(Action("Změnit heslo správce…", () => PasswordChange(false), () => Admin), Action("Změnit heslo hosta…", () => PasswordChange(true), () => Admin), Action("Zapomenout uložené heslo", () => { model.ForgetPassword(); return Task.CompletedTask; }, () => !model.Busy && model.Node != null)), "key")));
        Tool("Regiony", UI.Group("Regiony pro opakování", UI.Stack(Action("Načíst regiony", () => model.ReadRegions(), () => Admin), regions, UI.Secondary("Operace · úplný název regionu · rodič pouze pro put"), UI.Row(regionOp, regionName, regionParent), Action("Změnit a uložit region…", () => model.ChangeRegion(regionOp.SelectedItem as string ?? "", regionName.Text.Trim(), regionParent.Text.Trim()), () => Admin)), "repeater"));
        Tool("Advert a restart", UI.Group("Vysílání a napájení", UI.Stack(UI.Row(Action("Flood advert", () => model.Advert(false), () => Admin), Action("Zero-hop advert", () => model.Advert(true), () => Admin), Action("Restartovat…", () => model.Restart(), () => Admin)), UI.Secondary("Restart potvrďte až s připraveným návratem. Provedení se ověřuje samostatně podle stavu zařízení.")), "repeater")); Tab("Nástroje", tools);
        Tab("Prvotní nastavení", UI.Stack(UI.Group("Nastavte repeater pro svou síť", UI.Stack(UI.Secondary("Univerzální režim zachová načtené hodnoty. Volitelná česká předvolba připraví pouze návrhy; změny před uložením zkontrolujete."), cz, UI.Banner("Česká komunitní předvolba", "Flood 25 h · zero-hop 0 · dutycycle 10 % nebo af 9 · dvoubajtové hashe cesty. Nejde o univerzální parametry pro všechny sítě."), UI.Text("Veřejný kontakt na vlastníka (volitelné)"), owner, UI.Primary(Action("Načíst stav a připravit návrhy", async () => { await model.PrepareSetup(cz.IsChecked == true, owner.Text); if (model.Error == null && model.SetupSteps.Count > 0) tabs.SelectedIndex = 1; }, () => Admin)), setupStatus, setupReads), "check"), UI.Group("Hodiny po restartu", UI.Stack(UI.Secondary("Synchronizace času je samostatná ruční operace. Po restartu hodiny znovu ověřte."), Action("Synchronizovat hodiny…", () => model.SyncClock(), () => Admin)), "clock")));
        var history = new TabControl();
        var diagnosticInterval = UI.Input(DiagnosticPlan.HoursInput(model.Options.DiagnosticMinutes), 90);
        var diagnosticSamples = UI.Input(model.Options.DiagnosticSamples.ToString(), 70);
        var diagnosticPlan = UI.Secondary(""); var diagnosticProgress = UI.Text("");
        var diagnosticBar = new ProgressBar { Minimum = 0, Maximum = 6, Height = 6 };
        void PreviewDiagnostic()
        {
            try { var p = new DiagnosticPlan(DiagnosticPlan.MinutesFromHours(diagnosticInterval.Text), int.Parse(diagnosticSamples.Text), model.MeasurementRoute); diagnosticPlan.Text = $"Plán: {p.Samples} požadavky na stav, očekávané {p.Samples} odpovědi; délka {DiagnosticPlan.HoursText(p.DurationMinutes)}. První vzorek za {DiagnosticPlan.HoursText(p.IntervalMinutes)}. " + (model.MeasurementRoute == ServiceRoute.Known ? "Companion má platnou uloženou trasu; ta nezaručuje doručení." : "Flood / neznámá trasa: požadavek může přeposlat více uzlů."); }
            catch { diagnosticPlan.Text = "Zvolte interval 3–24 hodin, 1–6 vzorků a délku nejvýše 24 hodin."; }
        }
        diagnosticInterval.TextChanged += (_, _) => PreviewDiagnostic(); diagnosticSamples.TextChanged += (_, _) => PreviewDiagnostic(); PreviewDiagnostic();
        history.Items.Add(new TabItem { Header = "Zdraví repeateru", Content = UI.Stack(UI.Group("Časově omezené diagnostické měření", UI.Stack(
            UI.Row(UI.Text("Interval · hodiny"), diagnosticInterval, UI.Text("Počet vzorků"), diagnosticSamples), diagnosticPlan,
            UI.Secondary("Každý vzorek aktivně vyšle požadavek přes sdílenou LoRa síť a vyvolá odpověď. Výchozí plán: 3 požadavky po 4 h, první za 4 h a poslední za 12 h. Nejde o pasivní příjem. Žádný interval není univerzálně bezpečný. Historie a graf jsou místní; jejich prohlížení nic nevysílá."),
            UI.Row(Action("Spustit měření", async () => { var minutes = DiagnosticPlan.MinutesFromHours(diagnosticInterval.Text); if (!int.TryParse(diagnosticSamples.Text, out var count)) throw new MeshException("Zadejte počet vzorků jako celé číslo."); await model.SetDiagnosticOptions(minutes, count); model.SetMonitoring(true); }, () => Admin && !model.Monitoring), Action("Zastavit", () => { model.SetMonitoring(false); return Task.CompletedTask; }, () => model.Monitoring), Action("Načíst stav jednou", () => model.Ping(), () => Local && model.Node?.Stored == true)), diagnosticBar, diagnosticProgress,
            UI.Secondary("Ruční servis a měření sdílí 60 požadavků/h, z toho 12 bez známé trasy. Každý krok dávky se počítá samostatně. Prodleva mezi kroky je 15 s, při floodu / neznámé trase 60 s."),
            UI.Secondary("Zmeškané nebo obsazené termíny se přeskočí bez dohánění. Měření se samo neobnoví po chybě, odpojení, změně uzlu, ztrátě oprávnění ani spánku. Již odeslaný požadavek nelze vzít zpět; jeho omezené čekání se dokončí.")), "clock"), UI.Group("Historie napětí baterie", UI.Stack(UI.Secondary("Relativní rozsah · posledních 80 vzorků"), chart, sampleTable), "diagnostics")) });
        history.Items.Add(new TabItem { Header = "Snímky", Content = UI.Group("Snímky načtené konfigurace", UI.Stack(UI.Row(snapshotName, Action("Uložit načtené hodnoty", () => { model.CaptureSnapshot(snapshotName.Text); return Task.CompletedTask; }, () => Local && model.Node != null)), snapshots, UI.Row(Action("Exportovat…", async () => { if (snapshots.SelectedItem is ConfigSnapshot s) { s.Validate(); await SaveFile("MeshCore-snímek.json", JsonSerializer.Serialize(s, LocalStore.Json), "JSON|*.json"); } }), Action("Importovat…", async () => { OpenFileDialog open = new() { Filter = "JSON|*.json" }; if (open.ShowDialog(this) == true) { if (new FileInfo(open.FileName).Length > 1_000_000) throw new MeshException("Příliš velký soubor."); model.ImportSnapshot(await File.ReadAllTextAsync(open.FileName)); } }, () => !model.Busy && model.SelectedNode != null), Action("Porovnat a obnovit…", async () => { if (snapshots.SelectedItem is ConfigSnapshot s && Dialog.Select(this, "Vyberte hodnoty snímku", s.Values.Select(v => (v.Key, v.Key + " → " + v.Value))) is { } keys) await model.Restore(s, keys); }, () => Admin)), UI.Secondary("Snímky neobsahují hesla ani privátní klíče. Obnova vyžaduje živé porovnání a potvrzení.")), "folder") });
        history.Items.Add(new TabItem { Header = "Po restartu", Content = UI.Group("Nevyřízené změny", UI.Stack(pending, Action("Ověřit konfiguraci čtením", () => model.VerifyPending(), () => Admin), UI.Secondary("Hesla, regiony, restart a aktivaci rádia ověřte samostatným postupem. Odeslaný požadavek není důkaz provedené změny.")), "check") }); Tab("Historie a snímky", history);
        var selectedNodeContent = UI.Stack(UI.Columns(UI.Row(stored, authPill), verified), key, newNode, pendingBanner, tabs, dirtyBar);
        refreshPage = () =>
        {
            updating = true;
            try
            {
                if (toolsNode != model.SelectedNode) { toolsNode = model.SelectedNode; password.Clear(); owner.Clear(); accessKey.Clear(); regionName.Clear(); regionParent.Clear(); snapshotName.Clear(); cz.IsChecked = false; }
                diagnosticInterval.IsEnabled = diagnosticSamples.IsEnabled = !model.Monitoring && !model.Busy;
                PreviewDiagnostic();
                var measurement = model.Measurement;
                diagnosticBar.Maximum = measurement?.Plan.Samples ?? 6; diagnosticBar.Value = measurement?.Consumed ?? 0;
                diagnosticProgress.Text = measurement == null ? "Měření je vypnuté." : $"{(model.Monitoring ? "Probíhá" : "Ukončeno")} · termíny {measurement.Consumed}/{measurement.Plan.Samples} · uloženo {measurement.Received} · přeskočeno {measurement.Skipped} · zbývá {measurement.Remaining}" + (measurement.InFlight ? (measurement.Transmitted ? " · čekám na již odeslaný požadavek" : " · čekám na servisní limit") : "") + (model.NextMonitor is { } next ? $" · příští vzorek {next.LocalDateTime:g}" : "");
                setupStatus.Text = model.SetupSummary; setupReads.Text = string.Join("\n", model.SetupSteps.Select((s, i) => $"{i + 1}. {s.Command} · {s.State}")); setupReads.Visibility = model.SetupSteps.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
                UI.Source(nodes, model.Contacts.Where(c => c.Kind == 2).ToArray()); nodes.SelectedItem = model.Node; nodes.IsEnabled = !model.Busy;
                var titles = ((Grid)heading).Children.OfType<StackPanel>().First(); ((TextBlock)titles.Children[1]).Text = model.Node?.Name ?? "Správa repeateru";
                bool archived = model.Node == null && model.SelectedNode != null && model.Archive?.Nodes.ContainsKey(model.SelectedNode) == true;
                noNode.Visibility = model.Node == null ? Visibility.Visible : Visibility.Collapsed; selectedNodeContent.Visibility = model.Node != null || archived ? Visibility.Visible : Visibility.Collapsed;
                newNode.Visibility = model.Node?.Stored == false ? Visibility.Visible : Visibility.Collapsed;
                if (archived) tabs.SelectedIndex = 5; for (int i = 0; i < tabs.Items.Count; i++) ((TabItem)tabs.Items[i]).IsEnabled = model.Node != null || i == 5; login.Visibility = model.Admin ? Visibility.Collapsed : Visibility.Visible;
                ((TextBlock)stored.Child).Text = model.Node?.Stored == true ? "Uložený kontakt" : "Neuložený uzel";
                auth.Text = model.Admin ? "Správce ověřen" : "Bez přihlášení"; auth.SetResourceReference(TextBlock.ForegroundProperty, model.Admin ? "Accent" : "SecondaryText"); key.Text = model.Node?.Id ?? ""; verified.Text = model.Node != null && model.Verified.TryGetValue(model.Node.Id, out var date) ? "Odpověď " + date.LocalDateTime.ToString("T") : "Dostupnost neověřená";
                pendingBanner.Visibility = model.Operations.Pending.Count > 0 || model.Operations.RestartRequest != null ? Visibility.Visible : Visibility.Collapsed;
                foreach (var editor in editors) { if (editor.Editor.Text != editor.Field.Draft && !editor.Editor.IsKeyboardFocusWithin) editor.Editor.Text = editor.Field.Draft; editor.Editor.IsEnabled = Admin && editor.Field.Actual != null; editor.Status.Text = editor.Field.State + (editor.Field.Actual != null ? " · načteno: " + editor.Field.Actual : ""); }
                var parts = radioField.Draft.Split(','); for (int i = 0; i < radioValues.Length; i++) { if (!radioValues[i].IsKeyboardFocusWithin) radioValues[i].Text = i < parts.Length ? parts[i].Trim() : ""; radioValues[i].IsEnabled = Admin && radioField.Actual != null; } radioStatus.Text = radioField.State;
                metrics.Visibility = model.Status != null ? Visibility.Visible : Visibility.Collapsed;
                if (model.Status is { } s) { battery.Value.Text = $"{s.Battery / 1000d:F3} V"; uptime.Value.Text = UI.Duration(s.Uptime); rx.Value.Text = s.Received.ToString("N0"); rx.Detail.Text = $"{s.ReceivedFlood} flood · {s.ReceivedDirect} direct"; tx.Value.Text = s.Sent.ToString("N0"); tx.Detail.Text = $"{s.SentFlood} flood · {s.SentDirect} direct"; radioInfo.Text = $"RSSI posledního paketu        {s.LastRssi} dBm\n\nSNR posledního paketu          {s.LastSnr:F2} dB\n\nNoise floor · šum                    {s.Noise} dBm\n\nTyto metriky neměří celý spoj PC–repeater."; trafficInfo.Text = $"TX airtime                    {UI.Duration(s.TxAirtime)}\n\nRX airtime                    {(s.RxAirtime.HasValue ? UI.Duration(s.RxAirtime.Value) : "Firmware nevrátil")}\n\nVysílací fronta             {s.Queue} paketů\n\nDuplicity direct / flood        {s.DirectDuplicates} / {s.FloodDuplicates}\n\nChyby příjmu             {s.ReceiveErrors?.ToString() ?? "Firmware nevrátil"}"; }
                if (model.Status == null) { radioInfo.Text = "Stav zatím nebyl načtený."; trafficInfo.Text = "Stav zatím nebyl načtený."; }
                firmwareInfo.Text = $"Firmware: {(model.Firmware.Length == 0 ? "nenačteno" : model.Firmware)}\nDeska: {model.Board}\nHodiny: {model.Clock}";
                pending.Text = model.Operations.Pending.Count == 0 ? "Žádné evidované neověřené změny." : string.Join('\n', model.Operations.Pending.Select(p => $"{p.Date.LocalDateTime:g} · {p.Key} · čeká na ověření"));
                if (model.Operations.RestartRequest != null) pending.Text += $"\nRestart / pokles uptime: {model.Operations.RestartRequest?.LocalDateTime:g}\nDostupnost po restartu: {model.Operations.ReachableAfterRestart?.LocalDateTime:g}\nSynchronizace hodin: {model.Operations.ClockAfterRestart?.LocalDateTime:g}";
                telemetry.Text = model.TelemetryText; regions.Text = model.RegionText; UI.Source(acl, model.Access.ToArray()); UI.Source(neighbours, model.Neighbours.ToArray()); UI.Source(snapshots, model.Operations.Snapshots.AsEnumerable().Reverse().ToArray()); UI.Source(sampleTable, model.Operations.Samples.TakeLast(80).Reverse().ToArray()); Plot(); UpdateDirty();
            }
            finally { updating = false; }
        };
        return UI.Stack(heading, noNode, selectedNodeContent);
    }
    private async Task LoginDialog()
    {
        if (model.Node == null) return; PasswordBox password = new() { Padding = new(8), Margin = new(0, 6, 0, 10) }; var remember = UI.Check("Uložit do Správce přihlašovacích údajů Windows");
        var load = UI.Button("Vyplnit uložené heslo", () => { password.Password = model.LoadPassword() ?? ""; return Task.CompletedTask; });
        Dialog dialog = new(this, "Přihlášení správce", UI.Stack(UI.Text(model.Node.Name), password, remember, load), "Přihlásit"); dialog.Setup();
        if (dialog.ShowDialog() == true) { var secret = password.Password; password.Clear(); await model.Login(secret, remember.IsChecked == true); } else password.Clear();
    }
    private async Task PasswordChange(bool guest)
    {
        PasswordBox first = new() { Padding = new(8) }, second = new() { Padding = new(8) }; var remember = UI.Check("Uložit nové heslo správce v systému", true);
        Dialog dialog = new(this, guest ? "Heslo hosta" : "Heslo správce", UI.Stack(UI.Text("Nové heslo (1–15 UTF-8 bajtů bez mezer)"), first, UI.Text("Heslo znovu"), second, guest ? UI.Text("Heslo hosta se neukládá.") : remember), "Pokračovat"); dialog.Setup();
        if (dialog.ShowDialog() == true) { var secret = first.Password; bool same = secret == second.Password; first.Clear(); second.Clear(); if (!same) throw new MeshException("Hesla se liší."); await model.ChangePassword(secret, guest, remember.IsChecked == true); } else { first.Clear(); second.Clear(); }
    }
    private async Task SaveFile(string filename, string text, string filter = "Text|*.txt")
    { SaveFileDialog save = new() { FileName = filename, Filter = filter }; if (save.ShowDialog(this) == true) await File.WriteAllTextAsync(save.FileName, text); }
    private UIElement DiagnosticsPage()
    {
        var logs = UI.ReadText("", 200); var checks = UI.Table(("Test", "Test"), ("Výsledek uživatele", "Result"), ("FW companionu", "CompanionFirmware"), ("FW repeateru", "RepeaterFirmware"), ("Čas", "Date")); var test = UI.Combo(Controller.HardwareTests, 430); test.SelectedIndex = 0; var result = UI.Combo(new[] { "Neprovedeno", "Prošlo", "Selhalo" }, 150); result.SelectedIndex = 0;
        refreshPage = () => { logs.Text = string.Join('\n', model.Log.TakeLast(100).Select(l => $"{l.Date.LocalDateTime:T} · {l.Category}").Concat(model.ConnectionDiagnostics.Snapshot().TakeLast(100).Select(e => $"{e.Date.LocalDateTime:T} · BLE {BleText.Stage(e.Stage)} · {e.Outcome} · {e.CloseReason} {e.Failure?.Id}"))); UI.Source(checks, model.Library.Checks.Where(c => c.Account == model.Archive?.Account && c.Node == model.SelectedNode).ToArray()); };
        return UI.Stack(UI.Heading("Spojení pod kontrolou", "Diagnostika a ověření", "Skutečné události, bezpečný export a ruční kontroly zařízení."), UI.Text("Protokol firmware " + Codec.FirmwareCommit + ". Přenos: jeden BLE rámec v jednom GATT zápisu / notifikaci. Log obsahuje bezpečné kategorie a fáze BLE s číselnými stavy. Export lze vytvořit i po neúspěšném připojení. Obsah zpráv, příkazy, jména, klíče a hesla se neexportují."), logs,
            Action("Export připojení BLE/USB (bez identit)…", async () => { var report = model.BleDiagnosticReport(); if (Dialog.Ask(this, "Redigovaný export BLE · dostupný i bez připojení", report)) await SaveFile("MeshCore-BLE-diagnostika.json", report, "JSON|*.json"); }),
            Action("Náhled a export diagnostiky…", async () => { var report = model.DiagnosticReport(); if (Dialog.Ask(this, "Přesný obsah diagnostického exportu", report)) await SaveFile("MeshCore-diagnostika.json", report, "JSON|*.json"); }),
            UI.Group("Ruční ověření na skutečném zařízení", UI.Stack(UI.Text("Výsledek zaznamenáváte vy. Aplikace jej automaticky nepovažuje za úspěšný. Záznam je svázaný s companionem, repeaterem, oběma verzemi firmware, aplikací, Windows a architekturou. Nejdříve na kartě Stav načtěte verze."), test, result, Action("Zaznamenat výsledek kontroly", () => model.RecordCheck(test.SelectedItem as string ?? "", result.SelectedItem as string ?? ""), () => !model.Busy && model.Initialized && model.Firmware.Length > 0), checks)),
            UI.Text("Obnova po timeoutu: obnovte BLE relaci, znovu přihlaste správce a načtěte skutečný stav. Nejisté zápisy se neopakují automaticky.\n\nBluetooth je vypnutý: zapněte jej v Nastavení Windows. Přístup odmítnut: zkontrolujte oprávnění a systémové párování. Zařízení nedostupné: uvolněte spojení v telefonu, zkontrolujte vzdálenost a ovladače BLE adaptéru.\n\nTato Windows verze vyžaduje ověření WPF, párování, BLE a oznámení na skutečných Windows. Testy protokolu ani úspěšné sestavení nepředstavují test rádiového spojení."));
    }
}
