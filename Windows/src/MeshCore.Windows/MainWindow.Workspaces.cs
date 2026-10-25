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
    private UIElement ConnectionPage()
    {
        var title = UI.Text("Připojit companion", 21); title.FontWeight = FontWeights.SemiBold; var state = UI.Secondary(ble.State, 13); var badgeText = UI.Text("Odpojeno", 11); badgeText.Margin = new(0);
        var badge = new Border { Child = badgeText, Padding = new(9, 5, 9, 5), CornerRadius = new(15), Margin = new(12, 0, 0, 0), VerticalAlignment = VerticalAlignment.Top }; badge.SetResourceReference(Border.BackgroundProperty, "SubtleSurface");
        var connectionHeading = UI.Row(title, badge); var heroText = UI.Stack(connectionHeading, state); var avatar = UI.Avatar("connection", 70); avatar.Margin = new(0, 0, 18, 0); DockPanel hero = new() { Margin = new(0, 0, 0, 20) }; hero.Children.Add(avatar); hero.Children.Add(heroText);
        ListBox devices = new() { ItemsSource = ble.Devices, Height = 180, Margin = new(0, 10, 0, 12) }; var scanHint = UI.Secondary("Vyberte svůj companion podle názvu. Službu Nordic UART mohou používat i jiná zařízení.");
        var deviceResults = UI.Stack(scanHint, devices, UI.Row(UI.Primary(Action("Připojit vybrané", () => devices.SelectedItem is BleDevice d ? Connect(d.Address, null) : Task.CompletedTask, () => !connecting && !model.Busy && !ble.IsPairing)), Action("Systémově spárovat", () => { wantedAddress = null; return devices.SelectedItem is BleDevice d ? ble.Pair(d.Address) : Task.CompletedTask; }, () => !connecting && !model.Busy && !ble.Ready && !ble.IsPairing)));
        var heroCard = UI.Card(UI.Stack(hero, UI.Row(UI.WithIcon(Action("Hledat companiony", () => ble.Scan(), () => !connecting && !model.Busy && !ble.Ready && !ble.IsPairing), "search"), Action("Zastavit hledání", () => { ble.StopScan(); return Task.CompletedTask; }, () => ble.Scanning), Action("Nastavení Bluetooth", () => { OpenSettings(); return Task.CompletedTask; })), deviceResults));
        var pathName = UI.Text("Companion", 13); var pathModel = UI.Secondary("Bluetooth companion firmware", 11); var pathNode = UI.Text("Repeater", 13);
        UIElement Stage(string symbol, string name, string detail) { var icon = UI.Icon(symbol, 27); icon.HorizontalAlignment = HorizontalAlignment.Center; var a = UI.Text(name); a.TextAlignment = TextAlignment.Center; a.FontWeight = FontWeights.SemiBold; var b = UI.Secondary(detail, 11); b.TextAlignment = TextAlignment.Center; return UI.Stack(icon, a, b); }
        UIElement Link(string name) { var label = UI.Eyebrow(name); label.TextAlignment = TextAlignment.Center; var arrows = UI.Secondary("⇄", 22); arrows.TextAlignment = TextAlignment.Center; return UI.Stack(label, arrows); }
        var pathCompanion = UI.Stack(UI.Icon("chip", 27), pathName, pathModel); var pathRepeater = UI.Stack(UI.Icon("repeater", 27), pathNode, UI.Secondary("Vzdálená správa přes LoRa", 11));
        var link = UI.Card(UI.Columns(Stage("desktop", "Váš počítač", "MeshCore Servicer"), Link("BLE"), pathCompanion, Link("LoRa"), pathRepeater)); link.SetResourceReference(Border.BackgroundProperty, "SubtleSurface"); link.BorderThickness = new(0);
        var profiles = new StackPanel(); string profileSignature = "";
        var own = new Metric("Companion", "chip").Initialize(); var battery = new Metric("Baterie companionu", "battery", "Napětí hlášené companionem").Initialize(); var firmware = new Metric("Firmware", "folder").Initialize(); var metrics = UI.Columns(own.View, battery.View, firmware.View);
        var frequency = UI.Text("—", 16); var bandwidth = UI.Text("—", 16); var spreading = UI.Text("—", 16); var coding = UI.Text("—", 16); foreach (var field in new[] { frequency, bandwidth, spreading, coding }) field.FontFamily = UI.Mono;
        var radio = UI.Group("Rádio companionu", UI.Columns(UI.Stack(UI.Secondary("Frekvence"), frequency), UI.Stack(UI.Secondary("Šířka pásma"), bandwidth), UI.Stack(UI.Secondary("Spreading factor"), spreading), UI.Stack(UI.Secondary("Coding rate"), coding)), "repeater", "Skutečně načtené nastavení; připojením se nemění.");
        refreshPage = () =>
        {
            title.Text = model.Initialized ? model.Self?.Name ?? "Companion" : "Připojit companion"; state.Text = ble.State; badgeText.Text = model.Initialized ? "BLE připojeno" : connecting ? "Připojuji" : ble.IsPairing ? "Párování" : "Odpojeno";
            deviceResults.Visibility = ble.Devices.Count > 0 || ble.Scanning ? Visibility.Visible : Visibility.Collapsed;
            metrics.Visibility = radio.Visibility = model.Initialized ? Visibility.Visible : Visibility.Collapsed;
            own.Value.Text = model.Self?.Name ?? "—"; own.Detail.Text = model.Device?.Model ?? ""; battery.Value.Text = model.Battery is { } b ? $"{b / 1000d:F3} V" : "—"; firmware.Value.Text = model.Device?.Version ?? "—"; firmware.Detail.Text = model.Device?.Build ?? "";
            pathName.Text = model.Self?.Name ?? "Companion"; pathModel.Text = model.Device?.Model ?? "Bluetooth companion firmware"; pathNode.Text = model.Node?.Name ?? "Repeater";
            frequency.Text = model.Self is { } s ? $"{s.Frequency:F3} MHz" : "—"; bandwidth.Text = model.Self is { } r ? $"{r.Bandwidth:G} kHz" : "—"; spreading.Text = model.Self is { } sf ? $"SF{sf.Sf}" : "—"; coding.Text = model.Self is { } cr ? $"4/{cr.Cr}" : "—";
            var signature = string.Join('|', model.Library.Profiles.Select(p => p.Display + p.LastConnected)) + model.Busy + connecting;
            if (signature != profileSignature)
            {
                profileSignature = signature; profiles.Children.Clear();
                if (model.Library.Profiles.Count == 0) profiles.Children.Add(UI.Secondary("Profily se zobrazí po prvním připojení. Žádné zařízení není předvolené."));
                foreach (var p in model.Library.Profiles)
                {
                    var name = UI.Text(p.Display); name.FontWeight = FontWeights.SemiBold; var details = UI.Secondary($"Naposledy připojeno {p.LastConnected.LocalDateTime:g}", 11);
                    Button ProfileAction(string text, Func<Task> action) => UI.Button(text, () => Invoke(action));
                    var actions = UI.Row(ProfileAction("Přejmenovat", async () => { if (Dialog.Prompt(this, "Alias profilu", "Lokální název; nemění název zařízení.", p.Alias) is { } alias) await model.RenameProfile(p, alias); }), ProfileAction("Připojit…", () => Connect(p.BluetoothAddress, p.Account)), ProfileAction("Odstranit", () => model.DeleteProfile(p))); actions.IsEnabled = !model.Busy && !connecting;
                    var key = UI.Secondary(p.Account, 10); key.FontFamily = UI.Mono; profiles.Children.Add(UI.Stack(UI.Columns(UI.Stack(name, details), actions), key, UI.Divider()));
                }
            }
        };
        return UI.Stack(UI.Heading("Váš vstup do sítě", "Spojení začíná companionem", "Vyberte MeshCore companion a spravujte repeatery přes LoRa."), heroCard, link,
            UI.Group("Profily companionů", profiles, "contacts", "Místní názvy a vlastní volby konzole, obnovování BLE a diagnostického měření. Identita se ověřuje veřejným klíčem."), metrics, radio,
            UI.Columns(UI.Group("Před prvním připojením", UI.Stack(UI.Text("1   Zapněte companion"), UI.Secondary("Zařízení musí mít Bluetooth companion firmware."), UI.Text("2   Odpojte telefon"), UI.Secondary("Jiná aplikace může mít obsazené BLE spojení."), UI.Text("3   Potvrďte párování Windows"), UI.Secondary("Pokud je vyžadované, použijte skutečný PIN zařízení.")), "check"),
                UI.Group("Zařízení se nedaří najít?", UI.Stack(UI.Secondary("Zkontrolujte Bluetooth, dosah a oprávnění v Nastavení Windows. Název může obsahovat prefix firmwaru; ověřte jej podle načtené identity."), Action("Zkusit poslední companion", () => wantedAddress is { } a ? Connect(a, expectedIdentity) : Task.CompletedTask, () => !connecting && !model.Busy && wantedAddress != null && !ble.Ready)), "help")),
            UI.Secondary("Zavření okna ponechá aplikaci v oznamovací oblasti. Ukončení je dostupné v jejím menu."));
    }
    private static void OpenSettings() => System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("ms-settings:bluetooth") { UseShellExecute = true });
    private UIElement ContactsPage()
    {
        var heading = UI.Heading("Síťové uzly", "Kontakty", "Uložené identity a nově objevené uzly na jednom místě.", UI.Row(UI.WithIcon(Action("Načíst", () => model.LoadContacts(), () => Local), "refresh"), UI.Primary(Action("Objevit repeatery", () => model.Discover(), () => Local && model.Device?.Protocol >= 8))));
        var all = new Metric("Všechny uzly", "contacts").Initialize(); var repeaters = new Metric("Repeatery", "repeater").Initialize(); var unsaved = new Metric("Neuložené", "search").Initialize();
        var search = UI.Input("", 180); search.ToolTip = "Hledat podle názvu, klíče nebo typu"; var kind = UI.Combo(new[] { "Vše", "Companion", "Repeater", "Room server" }, 140); kind.SelectedIndex = 0;
        var list = new ListBox(); var listTitle = UI.Secondary("UZEL / ULOŽENÁ CESTA", 10); listTitle.Margin = new(14);
        DockPanel listPanel = new(); DockPanel.SetDock(listTitle, Dock.Top); listPanel.Children.Add(listTitle); listPanel.Children.Add(list); var listCard = UI.Card(listPanel, 0); listCard.Margin = new(0, 0, 16, 0);
        var inspector = UI.Card(UI.Empty("contacts", "Vyberte uzel", "Podrobnosti a akce se zobrazí tady."), 18); inspector.Margin = new(0); inspector.VerticalAlignment = VerticalAlignment.Top;
        var inspectorScroll = new ScrollViewer { Content = inspector, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        var content = new ResponsiveSplit(listCard, inspectorScroll, 320, 800, 340, sideOnRight: true);

        var compactCounts = UI.Secondary("");
        string? selected = null; bool updating = false; string rendered = "", inspectedSignature = "";
        void Inspect()
        {
            var c = model.Contacts.FirstOrDefault(c => c.Id == selected);
            var signature = (c == null ? "empty" : c.Id + c.Name + c.Kind + c.Stored + c.LastAdvert + model.Verified.GetValueOrDefault(c.Id).ToString("O") + model.DiscoveryInfo.GetValueOrDefault(c.Id, "")) + model.Busy + Local;
            if (signature == inspectedSignature) return; inspectedSignature = signature;
            if (c == null) { inspector.Child = UI.Empty("contacts", "Vyberte uzel", "Podrobnosti a akce se zobrazí tady."); return; }
            var name = UI.Text(c.Name, 19); name.FontWeight = FontWeights.SemiBold; var key = UI.Secondary(c.Id, 10); key.FontFamily = UI.Mono;
            var available = model.Verified.TryGetValue(c.Id, out var date) ? "Odpověď " + date.LocalDateTime.ToString("g") : "Neověřená";
            var actions = new StackPanel();
            if (c.Kind == 2) actions.Children.Add(UI.Primary(UI.Button("Spravovat repeater →", () => Invoke(async () => { if (await model.SelectNode(c.Id)) navigation.SelectedIndex = RepeaterSection; }))));
            if (c.Kind == 1 && c.Stored) actions.Children.Add(UI.Primary(UI.Button("Napsat zprávu", () => { model.SelectConversation("dm:" + c.Id[..12]); navigation.SelectedIndex = MessagesSection; return Task.CompletedTask; })));
            if (!c.Stored) { var save = UI.Button("Uložit do companionu", () => Invoke(() => model.StoreContact(c))); save.IsEnabled = Local; actions.Children.Add(save); }
            actions.Children.Add(UI.Button("Zkopírovat veřejný klíč", () => { Clipboard.SetText(c.Id); return Task.CompletedTask; })); actions.IsEnabled = !model.Busy;
            inspector.Child = UI.Stack(UI.NodeAvatar(c.Kind, 48), name, UI.Pill(c.Type), key, UI.Divider(), UI.Secondary("Kontakt"), UI.Text(c.Stored ? "Uložený v companionu" : "Zatím neuložený"), UI.Secondary("Dostupnost"), UI.Text(available), UI.Secondary(c.LastAdvert > 0 ? $"Advert podle companionu: {DateTimeOffset.FromUnixTimeSeconds(c.LastAdvert).LocalDateTime:g}" : "Čas advertu není dostupný"), UI.Secondary(model.DiscoveryInfo.GetValueOrDefault(c.Id, "")), actions);
        }
        list.SelectionChanged += (_, _) => { if (updating) return; selected = (list.SelectedItem as ListBoxItem)?.Tag as string; Inspect(); };
        void Render()
        {
            all.Value.Text = model.Contacts.Count.ToString(); repeaters.Value.Text = model.Contacts.Count(c => c.Kind == 2).ToString(); unsaved.Value.Text = model.Contacts.Count(c => !c.Stored).ToString();
            compactCounts.Text = $"Celkem {all.Value.Text} · Repeatery {repeaters.Value.Text} · Neuložené {unsaved.Value.Text}";
            var contacts = model.Contacts.Where(c => (kind.SelectedIndex == 0 || c.Type == kind.SelectedItem as string) && (c.Name + c.Id + c.Type).Contains(search.Text, StringComparison.OrdinalIgnoreCase)).OrderBy(c => c.Name).ToArray();
            var signature = string.Join('|', contacts.Select(c => c.Id + c.Name + c.Stored + c.Kind + c.PathLength)) + kind.SelectedIndex;
            if (signature != rendered)
            {
                rendered = signature; updating = true; list.Items.Clear();
                if (contacts.Length == 0) list.Items.Add(new ListBoxItem { Content = UI.Empty("contacts", "Žádný odpovídající uzel", "Načtěte kontakty nebo upravte vyhledávání a filtr."), IsHitTestVisible = false, Focusable = false });
                foreach (var c in contacts)
                {
                    var name = UI.Text(c.Name); name.FontWeight = FontWeights.SemiBold; var key = UI.Secondary(c.Id[..12], 10); key.FontFamily = UI.Mono; var details = UI.Secondary(c.Type + " · " + (c.PathLength == 255 ? "Cesta neznámá" : $"Uložená cesta: {Codec.Hops(c.PathLength)?.ToString() ?? "?"} hopů"), 11);
                    DockPanel row = new() { Margin = new(0, 3, 0, 3) }; var stored = UI.Secondary(c.Stored ? "Uloženo" : "Nový uzel", 10); stored.VerticalAlignment = VerticalAlignment.Center; stored.Margin = new(8, 0, 0, 0); DockPanel.SetDock(stored, Dock.Right); row.Children.Add(stored); row.Children.Add(UI.NodeAvatar(c.Kind, 36)); row.Children.Add(UI.Stack(name, details, key));
                    var item = new ListBoxItem { Content = row, Tag = c.Id }; list.Items.Add(item); if (c.Id == selected) list.SelectedItem = item;
                }
                updating = false;
            }
            listTitle.Text = $"UZEL / ULOŽENÁ CESTA · {contacts.Length} z {model.Contacts.Count}"; Inspect();
        }
        search.TextChanged += (_, _) => Render(); kind.SelectionChanged += (_, _) => Render(); refreshPage = Render;
        DockPanel page = new(); DockPanel.SetDock(heading, Dock.Top); page.Children.Add(heading); var metrics = UI.Columns(all.View, repeaters.View, unsaved.View); DockPanel.SetDock(metrics, Dock.Top); page.Children.Add(metrics); DockPanel.SetDock(compactCounts, Dock.Top); page.Children.Add(compactCounts);
        page.SizeChanged += (_, _) => { bool compact = page.ActualWidth < 800; metrics.Visibility = compact ? Visibility.Collapsed : Visibility.Visible; compactCounts.Visibility = compact ? Visibility.Visible : Visibility.Collapsed; };
        var filters = UI.Columns(UI.Stack(UI.Secondary("Hledat podle názvu, klíče nebo typu…"), search), UI.Stack(UI.Secondary("Zobrazit"), kind)); DockPanel.SetDock(filters, Dock.Top); page.Children.Add(filters);
        var footer = UI.Secondary("Uložení kontaktu a čas advertu neprokazují aktuální dostupnost. Ověření odpovědí má vlastní čas.", 11); footer.Margin = new(0, 12, 0, 0); DockPanel.SetDock(footer, Dock.Bottom); page.Children.Add(footer); page.Children.Add(content); return page;
    }
    private UIElement PreferencesPage()
    {
        var size = UI.Combo(new[] { "100 % · Výchozí", "115 % · Větší", "130 % · Velké", "150 % · Největší" }); size.SelectedIndex = Array.IndexOf(new[] { 100, 115, 130, 150 }, InterfaceScale);
        var options = model.Options; var theme = UI.Combo(new[] { "Systém", "Světlý", "Tmavý" }); theme.SelectedItem = model.Library.Theme;
        var reconnect = UI.Check("Automaticky obnovit neočekávaně přerušené BLE spojení", options.AutoReconnect); var notifications = UI.Check("Systémová oznámení nových zpráv", model.Library.Notifications); var sound = UI.Check("Zvuk oznámení (respektuje nastavení Windows)", model.Library.Sound); var preview = UI.Check("Zobrazovat v oznámení jméno a obsah zprávy", model.Library.NotificationText);
        var suggestions = UI.Check("Doplňování příkazů konzole", options.Suggestions); var writes = UI.Check("Nabízet také příkazy měnící konfiguraci", options.SuggestWrites); var help = UI.Check("Nápověda konzole", options.Help); var history = UI.Check("Nabízet bezpečnou historii této relace", options.History); var enter = UI.Check("Enter v konzoli odešle příkaz (jinak Ctrl+Enter)", options.EnterSends);
        return UI.Stack(UI.Heading("Vaše pracovní prostředí", "Nastavení aplikace", "Vzhled, oznámení, připojení a konzole na jednom místě."), UI.Text(model.Profile == null ? "Výchozí volby pro nové companiony." : "Volby profilu: " + model.Profile.Display), UI.Group("Vzhled a oznámení", UI.Stack(UI.Secondary("Barevný režim"), theme, UI.Secondary("Velikost rozhraní"), size, UI.Secondary("Systémové DPI se přebírá automaticky, rozložení reaguje na šířku okna. Ctrl + / Ctrl − zvětší či zmenší rozhraní, Ctrl 0 obnoví 100 %. V úzkém okně jsou názvy sekcí v nápovědě ikon."), notifications, sound, preview, UI.Text("Oznámení jsou při prvním spuštění vypnutá, obsah je standardně skrytý. Prvotní stažení fronty nevyvolává oznámení. Windows může upozornění potlačit režimem Nerušit."))), UI.Group("Připojení a diagnostika", UI.Stack(reconnect, UI.Text("Časově omezené měření se plánuje a výslovně spouští v Historii správy repeateru. Po spánku ani opětovném připojení se neobnovuje."))), UI.Group("Konzole", UI.Stack(suggestions, writes, help, history, enter)),
            Action("Uložit nastavení", async () => { options.AutoReconnect = reconnect.IsChecked == true; options.Suggestions = suggestions.IsChecked == true; options.SuggestWrites = writes.IsChecked == true; options.Help = help.IsChecked == true; options.History = history.IsChecked == true; options.EnterSends = enter.IsChecked == true; model.Library.Theme = theme.SelectedItem as string ?? "Systém"; model.Library.Notifications = notifications.IsChecked == true; model.Library.Sound = sound.IsChecked == true; model.Library.NotificationText = preview.IsChecked == true; model.Library.InterfaceScale = new[] { 100, 115, 130, 150 }[Math.Max(0, size.SelectedIndex)]; await model.SaveLibrary(); UI.Theme(model.Library.Theme); ApplyInterfaceScale(); }), Action("Ukončit aplikaci", Exit));
    }
}
