using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shell;
using System.Windows.Threading;
using MeshCore.Core;
using Microsoft.Win32;

namespace MeshCore.Windows;

public sealed partial class MainWindow : Window
{
    private readonly BleTransport ble;
    private readonly Controller model;
    private readonly ContentControl page = new();
    private readonly TextBlock header = UI.Text("Bez companionu", 12), status = UI.Text("Připraveno", 11), error = UI.Text("", 12);
    private readonly TextBlock sectionTitle = UI.Secondary("Připojení"), companionName = UI.Text("Companion odpojen", 12), companionHint = UI.Secondary("Vyberte Bluetooth zařízení", 10), repeaterName = UI.Text("", 13), repeaterAccess = UI.Secondary("Bez přihlášení", 11);
    private readonly TextBlock[] navigationCounts = new TextBlock[6];
    private Border? repeaterSummary, errorBanner;
    private Button? disconnectButton;
    private const int MessagesSection = 2, RepeaterSection = 3;
    private readonly ProgressBar progress = new() { Height = 3, Width = 65, IsIndeterminate = true, Margin = new(0, 0, 10, 0) };
    private readonly ListBox navigation = new() { BorderThickness = new(0), FontSize = 15, Margin = new(6, 0, 6, 0) };
    private Action refreshPage = () => { };
    private readonly DispatcherTimer timer;
    private Tray? tray;
    private bool exiting, connecting, refreshing, sleeping;
    private ulong? wantedAddress;
    private string? expectedIdentity;
    private DateTimeOffset reconnectAt;
    private int retrySeconds = 1;
    private readonly Dictionary<string, string> drafts = [];
    private string? draftAccount;
    public MainWindow(bool verification = false)
    {
        UI.Theme("Systém"); FontFamily = UI.Body; FontSize = 15; UseLayoutRounding = true; SnapsToDevicePixels = true; Title = "MeshCore Servicer · Windows"; Icon = System.Windows.Media.Imaging.BitmapFrame.Create(new Uri("pack://application:,,,/Assets/AppIcon.ico")); Width = Math.Min(1440, SystemParameters.WorkArea.Width - 48); Height = Math.Min(960, SystemParameters.WorkArea.Height - 48); MinWidth = Math.Min(760, Width); MinHeight = Math.Min(540, Height); WindowStartupLocation = WindowStartupLocation.CenterScreen;
        SetResourceReference(BackgroundProperty, "AppBackground"); SetResourceReference(ForegroundProperty, "AppForeground");
        ble = new(Dispatcher); model = new(ble, new CredentialStore(), new LocalStore(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MeshCoreServicer")));
        ble.PairingInteraction = request =>
        {
            if (request.Kind == "ProvidePin")
            {
                PasswordBox pin = new() { Padding = new(8) }; Dialog dialog = new(this, "Systémové párování Bluetooth", UI.Stack(UI.Text("Zadejte PIN z displeje nebo dokumentace vlastního companionu. PIN se neukládá."), pin)); dialog.Setup(); var accepted = dialog.ShowDialog() == true; var value = accepted ? pin.Password : null; pin.Clear(); return Task.FromResult(value);
            }
            var text = request.Kind == "DisplayPin" ? "Zadejte tento PIN na zařízení: " + request.Pin : request.Kind == "ConfirmPinMatch" ? "Souhlasí PIN na zařízení s údajem " + request.Pin + "?" : "Potvrďte systémové párování s vybraným companionem.";
            return Task.FromResult(Dialog.Ask(this, "Systémové párování Bluetooth", text) ? "potvrzeno" : null);
        };
        model.Confirm = (title, body) => Task.FromResult(Dialog.Ask(this, title, body)); model.Changed += Refresh; ble.Changed += Refresh;
        model.NotifyMessage += record =>
        {
            var account = model.Archive?.Account;
            tray?.Show(model.Library.NotificationText ? record.Title : "MeshCore Servicer", model.Library.NotificationText ? record.Sender + ": " + record.Text : "Přišla nová zpráva.", model.Library.Sound, () => { if (account == model.Archive?.Account) { model.SelectConversation(record.Conversation); navigation.SelectedIndex = MessagesSection; } });
        };
        BuildShell();
        PreviewKeyDown += async (_, e) =>
        {
            if (!Keyboard.Modifiers.HasFlag(ModifierKeys.Control) || (Keyboard.Modifiers & (ModifierKeys.Alt | ModifierKeys.Windows)) != 0) return;
            int[] scales = [100, 115, 130, 150]; int index = Array.IndexOf(scales, InterfaceScale);
            int? scale = e.Key switch { Key.OemPlus or Key.Add => scales[Math.Min(scales.Length - 1, index + 1)], Key.OemMinus or Key.Subtract => scales[Math.Max(0, index - 1)], Key.D0 or Key.NumPad0 => 100, _ => null };
            if (scale == null) return; e.Handled = true; model.Library.InterfaceScale = scale.Value; ApplyInterfaceScale(); await Invoke(() => model.SaveLibrary());
        };
        PreviewKeyDown += (_, e) => { if (Keyboard.Modifiers == ModifierKeys.Control && e.Key >= Key.D1 && e.Key <= Key.D6) { navigation.SelectedIndex = e.Key - Key.D1; e.Handled = true; } else if (Keyboard.Modifiers == ModifierKeys.Control && e.Key == Key.OemComma) { navigation.SelectedIndex = 6; e.Handled = true; } };
        timer = new(TimeSpan.FromMilliseconds(700), DispatcherPriority.Background, async (_, _) => await Tick(), Dispatcher); timer.Stop();
        if (!verification) Loaded += async (_, _) => { await model.Start(); UI.Theme(model.Library.Theme); ApplyInterfaceScale(); tray = new(ShowWindow, () => _ = Exit()); navigation.SelectedIndex = 0; timer.Start(); Refresh(); };
        Activated += (_, _) => Reading(); Deactivated += (_, _) => { model.ReadingConversation = false; };
        StateChanged += (_, _) => Reading(); IsVisibleChanged += (_, _) => Reading();
        Closing += (_, e) => { if (!exiting) { e.Cancel = true; Hide(); model.ReadingConversation = false; } };
        if (!verification) { SystemEvents.PowerModeChanged += PowerChanged; SystemEvents.UserPreferenceChanged += PreferencesChanged; }
    }
    private void PreferencesChanged(object sender, UserPreferenceChangedEventArgs e) => Dispatcher.BeginInvoke(() => { if (model.Library.Theme == "Systém") UI.Theme("Systém"); });
    private void PowerChanged(object sender, PowerModeChangedEventArgs e) => Dispatcher.BeginInvoke(() =>
    { if (e.Mode == PowerModes.Suspend) { sleeping = true; model.SetMonitoring(false); ble.Disconnect(); } else if (e.Mode == PowerModes.Resume) { sleeping = false; reconnectAt = DateTimeOffset.UtcNow.AddSeconds(3); } });
    private void ShowWindow() { Show(); if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal; Activate(); Reading(); }
    private async Task Exit()
    {
        if (exiting) return;
        if (model.Busy && !Dialog.Ask(this, "Ukončit probíhající operaci?", "Výsledek odeslaného požadavku může zůstat neověřený. Před opakováním znovu načtěte stav.")) return;
        exiting = true; wantedAddress = null; timer.Stop(); ble.Dispose(); await model.Flush(); tray?.Dispose(); SystemEvents.PowerModeChanged -= PowerChanged; SystemEvents.UserPreferenceChanged -= PreferencesChanged; Close(); Application.Current.Shutdown();
    }
    private void Reading() { model.ReadingConversation = navigation.SelectedIndex == MessagesSection && IsVisible && IsActive && WindowState != WindowState.Minimized; model.MarkRead(); }
    private async Task Invoke(Func<Task> action)
    { try { await action(); } catch (Exception ex) { MessageBox.Show(this, model.Clean(ex.Message), "MeshCore Servicer", MessageBoxButton.OK, MessageBoxImage.Warning); } finally { Refresh(); } }
    private Button Action(string title, Func<Task> action, Func<bool>? enabled = null)
    { var button = UI.Button(title, () => Invoke(action), enabled); buttons.Add((button, enabled ?? (() => true))); return button; }
    private readonly List<(Button Button, Func<bool> Enabled)> buttons = [];
    private bool Local => model.Initialized && !model.Busy && !model.Session.RequiresReconnect && !connecting;
    private bool Admin => Local && model.Admin;
    private async Task Tick()
    {
        if (exiting || sleeping || connecting || ble.IsPairing) return;
        if (wantedAddress != null && !ble.Ready && model.Options.AutoReconnect && DateTimeOffset.UtcNow >= reconnectAt)
        { reconnectAt = DateTimeOffset.UtcNow.AddSeconds(retrySeconds); retrySeconds = Math.Min(30, retrySeconds * 2); await Connect(wantedAddress.Value, expectedIdentity, true); }
        await Invoke(() => model.Tick());
    }
    private async Task Connect(ulong address, string? identity, bool retry = false)
    {
        if (connecting || ble.IsPairing || model.Busy) return; connecting = true; Refresh();
        try
        {
            await ble.Connect(address); await model.Initialize(address, identity);
            if (!model.Initialized) { wantedAddress = null; ble.Disconnect(); return; }
            wantedAddress = address; expectedIdentity = model.Self!.Id; retrySeconds = 1; reconnectAt = DateTimeOffset.UtcNow.AddSeconds(2);
        }
        catch (Exception ex)
        {
            ble.Disconnect(); if (!retry) { wantedAddress = null; MessageBox.Show(this, model.Clean(ex.Message), "Připojení se nezdařilo", MessageBoxButton.OK, MessageBoxImage.Warning); }
            reconnectAt = DateTimeOffset.UtcNow.AddSeconds(retrySeconds);
        }
        finally { connecting = false; Refresh(); }
    }
    private void Navigate()
    {
        buttons.Clear(); refreshPage = () => { }; model.ReadingConversation = false;
        var content = navigation.SelectedIndex switch { 0 => ConnectionPage(), 1 => ContactsPage(), 2 => MessagesPage(), 3 => RepeaterPage(), 4 => ConsolePage(), 5 => DiagnosticsPage(), _ => PreferencesPage() };
        var frame = new Border { Child = content, Padding = new(24), MaxWidth = navigation.SelectedIndex is 1 or 2 or 4 ? 1600 : 1440, HorizontalAlignment = HorizontalAlignment.Stretch };
        ScrollViewer viewport = new() { Content = frame, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        int section = navigation.SelectedIndex;
        void FitPage() { frame.Padding = new(viewport.ActualWidth < 820 ? 16 : 28); if (section is 1 or 2 or 4) frame.Height = LayoutPolicy.WorkspaceHeight(section, Math.Max(0, viewport.ActualWidth - frame.Padding.Left - frame.Padding.Right), viewport.ActualHeight); }
        viewport.SizeChanged += (_, _) => FitPage(); page.Content = viewport;

        sectionTitle.Text = new[] { "Připojení", "Kontakty", "Zprávy", "Správa repeateru", "Konzole", "Diagnostika", "Nastavení" }[navigation.SelectedIndex]; Reading(); Refresh();
    }
    private void Refresh()
    {
        if (!Dispatcher.CheckAccess()) { Dispatcher.BeginInvoke(Refresh); return; } if (refreshing) return; refreshing = true;
        try
        {
            if (draftAccount != model.Archive?.Account) { drafts.Clear(); draftAccount = model.Archive?.Account; }
            header.Text = model.Initialized ? $"BLE  ●  {model.Self?.Name}  {model.Battery / 1000d:F2} V" : connecting ? "Připojuji companion…" : "BLE  ○  Bez companionu";
            companionName.Text = model.Initialized ? model.Self?.Name ?? "Companion" : "Companion odpojen";
            companionHint.Text = model.Initialized ? "Připojeno přes Bluetooth" : connecting ? "Připojuji…" : "Vyberte Bluetooth zařízení";
            repeaterName.Text = model.Node?.Name ?? ""; repeaterAccess.Text = model.Admin ? "Správce ověřen" : "Bez přihlášení";
            if (repeaterSummary != null) repeaterSummary.Visibility = model.Node == null || LayoutPolicy.Compact(shell.ActualWidth) || shell.ActualHeight < 700 ? Visibility.Collapsed : Visibility.Visible;
            navigationCounts[1].Text = model.Contacts.Count == 0 ? "" : model.Contacts.Count.ToString(); navigationCounts[2].Text = model.Unread == 0 ? "" : model.Unread.ToString(); navigationCounts[3].Text = model.Settings.Any(f => f.Dirty) ? "●" : "";
            if (disconnectButton != null) disconnectButton.IsEnabled = ble.Ready && !connecting;
            status.Text = (connecting ? "Připojuji…" : model.Progress) + (model.Monitoring ? $" · měření: další {model.NextMonitor?.LocalDateTime:t}" : "");
            progress.Visibility = model.Busy || connecting || ble.IsPairing ? Visibility.Visible : Visibility.Collapsed;
            error.Text = model.Error ?? model.StorageError ?? "";
            if (model.Session.RequiresReconnect && !error.Text.Contains("obnovte BLE", StringComparison.OrdinalIgnoreCase)) error.Text += "  Obnovte BLE relaci; zápis automaticky neopakujte.";
            if (errorBanner != null) errorBanner.Visibility = error.Text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
            refreshPage(); foreach (var b in buttons.ToArray()) b.Button.IsEnabled = b.Enabled();
            Title = (model.Unread > 0 ? $"({model.Unread}) " : "") + "MeshCore Servicer · Windows";
            TaskbarItemInfo ??= new(); TaskbarItemInfo.Description = model.Unread > 0 ? $"{model.Unread} nepřečtených zpráv" : "MeshCore Servicer";
            if (model.Unread > 0) { DrawingGroup draw = new(); using (var context = draw.Open()) { context.DrawEllipse(Brushes.Teal, null, new Point(8, 8), 8, 8); context.DrawEllipse(Brushes.White, null, new Point(8, 8), 3, 3); } TaskbarItemInfo.Overlay = new DrawingImage(draw); } else TaskbarItemInfo.Overlay = null;
        }
        finally { refreshing = false; }
    }
}
