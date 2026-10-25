using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Media;
using System.Windows.Shapes;

namespace MeshCore.Windows;
internal static class UI
{
    private static bool stylesLoaded;
    public static readonly FontFamily Mono = new("Cascadia Mono, Consolas");
    public static readonly FontFamily Body = new("Segoe UI Variable Text, Segoe UI");
    public static TextBlock Text(string text, double size = 13) => new() { Text = text, FontSize = Math.Max(12, size + 2), TextWrapping = TextWrapping.Wrap, Margin = new(0, 0, 0, 8) };
    public static TextBlock Secondary(string text, double size = 12) { var label = Text(text, size); label.SetResourceReference(TextBlock.ForegroundProperty, "SecondaryText"); return label; }
    public static TextBlock Eyebrow(string text) { var label = Text(text.ToUpperInvariant(), 10); label.FontWeight = FontWeights.Bold; label.SetResourceReference(TextBlock.ForegroundProperty, "Accent"); return label; }
    public static StackPanel Stack(params UIElement[] children) { StackPanel panel = new(); foreach (var child in children) panel.Children.Add(child); return panel; }
    public static WrapPanel Row(params UIElement[] children) { WrapPanel panel = new() { Margin = new(0, 3, 0, 8) }; foreach (var child in children) panel.Children.Add(child); return panel; }
    public static Grid Columns(params UIElement[] children)
    {
        return new ResponsiveColumns(240, children);
    }
    public static Grid Heading(string eyebrow, string title, string subtitle, UIElement? actions = null)
    {
        var heading = Text(title, 27); heading.FontWeight = FontWeights.Bold;
        return new ResponsiveHeading(Stack(Eyebrow(eyebrow), heading, Secondary(subtitle, 13)), actions) { Margin = new(0, 0, 0, 20) };
    }

    public static Border Card(UIElement content, int padding = 20)
    { var border = new Border { Child = content, Padding = new(padding), CornerRadius = new(14), BorderThickness = new(1), Margin = new(0, 0, 0, 20) }; border.SetResourceReference(Border.BackgroundProperty, "Surface"); border.SetResourceReference(Border.BorderBrushProperty, "AppBorder"); return border; }
    public static Border Group(string title, UIElement content, string symbol = "tools", string? subtitle = null)
    {
        var name = Text(title, 14); name.FontWeight = FontWeights.SemiBold; var titles = Stack(name); if (subtitle != null) titles.Children.Add(Secondary(subtitle));
        DockPanel header = new() { Margin = new(0, 0, 0, 12) }; var icon = Icon(symbol, 18); icon.Margin = new(0, 1, 10, 0); header.Children.Add(icon); header.Children.Add(titles); return Card(Stack(header, content));
    }
    public static Border Pill(string text, bool active = false) { var label = Text(text, 11); label.Margin = new(0); label.FontWeight = FontWeights.Medium; label.SetResourceReference(TextBlock.ForegroundProperty, active ? "Accent" : "SecondaryText"); var pill = new Border { Child = label, CornerRadius = new(15), Padding = new(9, 5, 9, 5), Margin = new(0, 0, 8, 0) }; pill.SetResourceReference(Border.BackgroundProperty, active ? "Selection" : "SubtleSurface"); return pill; }
    public static Border Banner(string title, string detail, bool warning = false)
    { var name = Text(title); name.FontWeight = FontWeights.SemiBold; var border = Card(Stack(name, Secondary(detail)), 14); border.CornerRadius = new(10); border.SetResourceReference(Border.BackgroundProperty, warning ? "WarningSurface" : "Selection"); border.SetResourceReference(Border.BorderBrushProperty, warning ? "WarningBorder" : "AppBorder"); return border; }
    public static Border Empty(string symbol, string title, string description)
    {
        var icon = Avatar(symbol, 64); icon.HorizontalAlignment = HorizontalAlignment.Center; var heading = Text(title, 17); heading.FontWeight = FontWeights.SemiBold; heading.TextAlignment = TextAlignment.Center; var detail = Secondary(description, 13); detail.MaxWidth = 410; detail.TextAlignment = TextAlignment.Center; detail.HorizontalAlignment = HorizontalAlignment.Center;
        var stack = Stack(icon, heading, detail); stack.Margin = new(24); stack.VerticalAlignment = VerticalAlignment.Center; return new() { Child = stack, MinHeight = 220 };
    }
    public static Button Button(string title, Func<Task> action, Func<bool>? enabled = null)
    {
        Button button = new() { Content = title, Margin = new(0, 0, 8, 6) };
        button.Click += async (_, _) => { if (!button.IsEnabled) return; button.IsEnabled = false; try { await action(); } finally { button.IsEnabled = enabled?.Invoke() ?? true; } }; return button;
    }
    public static Button Primary(Button button) { button.SetResourceReference(FrameworkElement.StyleProperty, "PrimaryButton"); return button; }
    public static Button WithIcon(Button button, string symbol) { var label = Text(button.Content?.ToString() ?? ""); label.Margin = new(7, 0, 0, 0); var icon = Icon(symbol, 15); icon.SetBinding(Shape.StrokeProperty, new Binding("Foreground") { Source = button }); button.Content = new StackPanel { Orientation = Orientation.Horizontal, Children = { icon, label } }; return button; }
    public static TextBox Input(string value = "", double width = 200) => new() { Text = value, MinWidth = width, Margin = new(0, 0, 8, 8), VerticalContentAlignment = VerticalAlignment.Center };
    public static ComboBox Combo(IEnumerable items, double width = 210) => new() { ItemsSource = items, MinWidth = width, Margin = new(0, 0, 8, 8), Padding = new(10, 6, 28, 6), MaxDropDownHeight = 320 };
    public static DataGrid Table(params (string Title, string Path)[] columns)
    {
        DataGrid grid = new() { AutoGenerateColumns = false, IsReadOnly = true, CanUserAddRows = false, SelectionMode = DataGridSelectionMode.Extended, SelectionUnit = DataGridSelectionUnit.FullRow, MinHeight = 100, MaxHeight = 400, Margin = new(0, 5, 0, 12), HeadersVisibility = DataGridHeadersVisibility.Column, GridLinesVisibility = DataGridGridLinesVisibility.Horizontal };
        foreach (var (title, path) in columns) grid.Columns.Add(new DataGridTextColumn { Header = title, Binding = new Binding(path), MinWidth = 140, Width = new DataGridLength(1, DataGridLengthUnitType.Star) }); return grid;
    }
    public static CheckBox Check(string text, bool value = false) => new() { Content = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap }, IsChecked = value, Margin = new(0, 5, 8, 8), VerticalContentAlignment = VerticalAlignment.Center };
    public static TextBox ReadText(string text = "", double height = 110) => new() { Text = text, IsReadOnly = true, TextWrapping = TextWrapping.Wrap, AcceptsReturn = true, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Height = height, Padding = new(8), Margin = new(0, 4, 0, 12) };
    public static Border Divider() { var border = new Border { Height = 1, Margin = new(0, 8, 0, 12) }; border.SetResourceReference(Border.BackgroundProperty, "AppBorder"); return border; }
    public static void Source(ItemsControl control, IEnumerable items)
    { if (control.ItemsSource != null && control.ItemsSource.Cast<object>().SequenceEqual(items.Cast<object>())) return; var selected = (control as System.Windows.Controls.Primitives.Selector)?.SelectedItem; control.ItemsSource = items; if (selected != null && control is System.Windows.Controls.Primitives.Selector selector && items.Cast<object>().Contains(selected)) selector.SelectedItem = selected; }
    public static Path Icon(string name, double size = 20)
    {
        string data = name switch
        {
            "connection" => "M9,2 L9,8 M15,2 L15,8 M7,7 L17,7 L17,13 L14,16 L14,22 L10,22 L10,16 L7,13 Z",
            "contacts" => "M8,11 A4,4 0 1 0 8,3 A4,4 0 1 0 8,11 M2,21 L2,18 C2,13 14,13 14,18 L14,21 Z M16,4 C22,3 23,11 17,12 M17,15 C22,15 23,18 23,21",
            "messages" => "M3,3 L17,3 Q19,3 19,5 L19,13 Q19,15 17,15 L9,15 L5,19 L5,15 L3,15 Q1,15 1,13 L1,5 Q1,3 3,3 M21,8 L23,8 L23,19 L20,19 L20,23 L16,19 L11,19",
            "repeater" => "M12,12 L12,23 M10,23 L14,23 M8,8 C5,11 5,15 8,18 M16,8 C19,11 19,15 16,18 M5,4 C0,9 0,17 5,22 M19,4 C24,9 24,17 19,22 M12,9 A2,2 0 1 0 12,13 A2,2 0 1 0 12,9",
            "console" => "M2,3 L22,3 L22,21 L2,21 Z M6,8 L10,12 L6,16 M12,16 L18,16",
            "diagnostics" => "M1,13 L6,13 L9,3 L12,22 L16,8 L18,13 L23,13",
            "search" => "M10,2 A8,8 0 1 0 10,18 A8,8 0 1 0 10,2 M16,16 L23,23",
            "refresh" => "M20,8 A9,9 0 1 0 21,16 M20,2 L20,8 L14,8",
            "battery" => "M2,6 L20,6 L20,18 L2,18 Z M23,9 L23,15 M5,9 L16,9 L16,15 L5,15 Z",
            "clock" => "M12,2 A10,10 0 1 0 12,22 A10,10 0 1 0 12,2 M12,6 L12,12 L7,12",
            "down" => "M19,5 L5,19 M5,9 L5,19 L15,19",
            "up" => "M5,19 L19,5 M9,5 L19,5 L19,15",
            "lock" => "M6,10 L18,10 L18,22 L6,22 Z M8,10 L8,6 A4,4 0 0 1 16,6 L16,10",
            "server" => "M2,2 L22,2 L22,10 L2,10 Z M2,14 L22,14 L22,22 L2,22 Z M5,6 L7,6 M5,18 L7,18 M15,6 L19,6 M15,18 L19,18",
            "chip" => "M5,5 L19,5 L19,19 L5,19 Z M8,8 L16,8 L16,16 L8,16 Z M8,1 L8,5 M16,1 L16,5 M8,19 L8,23 M16,19 L16,23 M1,8 L5,8 M1,16 L5,16 M19,8 L23,8 M19,16 L23,16",
            "desktop" => "M2,3 L22,3 L22,17 L2,17 Z M12,17 L12,22 M7,22 L17,22",
            "settings" => "M2,5 L22,5 M2,12 L22,12 M2,19 L22,19 M6,2 L6,8 M17,9 L17,15 M9,16 L9,22",
            "send" => "M12,22 L12,2 M5,9 L12,2 L19,9",
            "copy" => "M8,8 L21,8 L21,23 L8,23 Z M4,17 L2,17 L2,1 L15,1 L15,4",
            "key" => "M8,3 A6,6 0 1 0 8,15 A6,6 0 1 0 8,3 M13,12 L22,21 M18,17 L21,14 M21,20 L24,17",
            "help" => "M12,2 A10,10 0 1 0 12,22 A10,10 0 1 0 12,2 M9,8 C9,3 18,6 14,10 L12,12 L12,15 M12,18 L12,19",
            "folder" => "M2,5 L10,5 L12,8 L22,8 L22,22 L2,22 Z",
            "check" => "M3,12 L9,19 L22,4",
            "hash" => "M9,2 L5,22 M18,2 L14,22 M2,8 L23,8 M1,16 L22,16",
            "logout" => "M15,4 L3,4 L3,20 L15,20 M10,12 L23,12 M18,7 L23,12 L18,17",
            "tools" => "M4,3 L4,10 L8,13 L19,24 L23,20 L12,9 L9,5 L9,1 M4,3 L9,5",
            _ => "M4,6 L20,6 M4,12 L20,12 M4,18 L20,18"
        };
        var path = new Path { Data = Geometry.Parse(data), Width = Math.Max(18, size), Height = Math.Max(18, size), Stretch = Stretch.Uniform, StrokeThickness = 1.8, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, StrokeLineJoin = PenLineJoin.Round, VerticalAlignment = VerticalAlignment.Center };
        path.SetResourceReference(Shape.StrokeProperty, "Accent"); return path;
    }
    public static Border Avatar(string symbol, double size = 40) { var border = new Border { Child = Icon(symbol, size * .44), Width = size, Height = size, CornerRadius = new(size * .28), Margin = new(0, 0, 12, 12) }; border.SetResourceReference(Border.BackgroundProperty, "Selection"); return border; }
    public static Border NodeAvatar(byte kind, double size = 40)
    {
        var avatar = Avatar(kind switch { 1 => "contacts", 2 => "repeater", 3 => "server", _ => "chip" }, size);
        var tone = kind switch { 1 => "NodeBlue", 3 => "NodePurple", 4 => "NodeOrange", _ => "Accent" };
        ((Shape)avatar.Child).SetResourceReference(Shape.StrokeProperty, tone); avatar.SetResourceReference(Border.BackgroundProperty, tone == "Accent" ? "Selection" : tone + "Surface"); return avatar;
    }
    public static Viewbox MeshMark(double size = 32)
    {
        Canvas canvas = new() { Width = 42, Height = 42 }; var lines = new Path { Data = Geometry.Parse("M7,8 L35,8 L21,34 Z"), StrokeThickness = 2, StrokeDashArray = new DoubleCollection([1, 2]) }; lines.SetResourceReference(Shape.StrokeProperty, "Accent"); canvas.Children.Add(lines);
        foreach (var (x, y) in new[] { (7, 8), (35, 8), (21, 34) }) { Ellipse circle = new() { Width = 9, Height = 9, StrokeThickness = 3 }; circle.SetResourceReference(Shape.StrokeProperty, "Accent"); circle.SetResourceReference(Shape.FillProperty, "SidebarBackground"); Canvas.SetLeft(circle, x - 4.5); Canvas.SetTop(circle, y - 4.5); canvas.Children.Add(circle); }
        return new() { Child = canvas, Width = size, Height = size };
    }
    public static string Duration(uint seconds) { var t = TimeSpan.FromSeconds(seconds); return t.TotalDays >= 1 ? $"{(int)t.TotalDays} d {t.Hours} h {t.Minutes} min" : t.TotalHours >= 1 ? $"{t.Hours} h {t.Minutes} min" : t.TotalMinutes >= 1 ? $"{t.Minutes} min {t.Seconds} s" : $"{t.Seconds} s"; }
    public static void Theme(string mode)
    {
        var resources = Application.Current.Resources;
        bool dark = mode == "Tmavý";
        if (mode == "Systém") { try { dark = (int?)Microsoft.Win32.Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1) == 0; } catch { dark = false; } }
        void Color(string key, string light, string night) => resources[key] = new SolidColorBrush((System.Windows.Media.Color)ColorConverter.ConvertFromString(dark ? night : light));
        Color("AppBackground", "#FFFFFF", "#1E1E1E"); Color("Surface", "#FFFFFF", "#1E1E1E"); Color("SidebarBackground", "#FAFAFA", "#1C1C1C"); Color("AppForeground", "#252525", "#E3E3E3"); Color("SecondaryText", "#626262", "#B8B8B8"); Color("TertiaryText", "#707070", "#A4A4A4"); Color("AppBorder", "#E8E8E8", "#333333"); Color("Accent", "#056E63", "#59D4C2"); Color("OnAccent", "#FFFFFF", "#102823"); Color("Selection", "#DFEBE9", "#233632"); Color("SubtleSurface", "#F5F5F5", "#252525"); Color("ButtonBackground", "#EEEEEE", "#303030"); Color("InputBackground", "#F6F6F6", "#242424"); Color("Hover", "#F0F3F2", "#282D2B"); Color("SegmentedBackground", "#EEEEEE", "#303030"); Color("SegmentSelected", "#FFFFFF", "#4A4A4A"); Color("WarningSurface", "#FFF6E9", "#31291F"); Color("WarningBorder", "#EDCCA0", "#664322"); Color("WarningText", "#9D5C0A", "#F1AF52"); Color("TerminalBackground", "#101416", "#101416"); Color("TerminalHeader", "#191F21", "#191F21"); Color("TerminalText", "#DBE0DF", "#DBE0DF"); Color("TerminalAccent", "#59D4C2", "#59D4C2"); Color("TerminalSecondary", "#A4ADAA", "#A4ADAA");
        Color("NodeBlue", "#2F75C9", "#78B8FF"); Color("NodeBlueSurface", "#EAF2FC", "#203044"); Color("NodePurple", "#8055B9", "#CA9DF4"); Color("NodePurpleSurface", "#F2ECFA", "#35283E"); Color("NodeOrange", "#AA661B", "#F5B061"); Color("NodeOrangeSurface", "#FCF0E1", "#3A2C1E");
        resources[SystemColors.WindowBrushKey] = resources["Surface"]; resources[SystemColors.WindowTextBrushKey] = resources["AppForeground"]; resources[SystemColors.ControlTextBrushKey] = resources["AppForeground"]; resources[SystemColors.ControlBrushKey] = resources["ButtonBackground"]; resources[SystemColors.HighlightBrushKey] = resources["Selection"]; resources[SystemColors.HighlightTextBrushKey] = resources["Accent"];
        if (!stylesLoaded) { resources.MergedDictionaries.Add(new ResourceDictionary { Source = new Uri("/MeshCoreServicer;component/Assets/Theme.xaml", UriKind.Relative) }); stylesLoaded = true; }
    }
}
internal sealed class Metric(string title, string symbol, string detail = "")
{
    public TextBlock Value { get; } = UI.Text("—", 24);
    public TextBlock Detail { get; } = UI.Secondary(detail, 11);
    public Border View { get; } = Make();
    private static Border Make() => UI.Card(new StackPanel());
    public Metric Initialize()
    { Value.FontWeight = FontWeights.SemiBold; var label = UI.Secondary(title); var icon = UI.Icon(symbol, 17); icon.HorizontalAlignment = HorizontalAlignment.Right; DockPanel heading = new(); DockPanel.SetDock(icon, Dock.Right); heading.Children.Add(icon); heading.Children.Add(label); View.Child = UI.Stack(heading, Value, Detail); View.Padding = new(17); View.CornerRadius = new(12); return this; }
}
internal sealed class Dialog(Window owner, string title, UIElement body, string accept = "Potvrdit") : Window
{
    public void Setup()
    {
        SetResourceReference(BackgroundProperty, "AppBackground"); SetResourceReference(ForegroundProperty, "AppForeground"); FontFamily = UI.Body; FontSize = 15; Owner = owner; Title = title; Width = Math.Min(720, SystemParameters.WorkArea.Width - 48); MaxHeight = Math.Max(300, SystemParameters.WorkArea.Height - 64); SizeToContent = SizeToContent.Height; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        DockPanel layout = new() { Margin = new(24) }; var cancel = UI.Button("Zrušit", () => { DialogResult = false; return Task.CompletedTask; }); cancel.IsCancel = true; var confirm = UI.Primary(UI.Button(accept, () => { DialogResult = true; return Task.CompletedTask; })); confirm.IsDefault = true; var buttons = UI.Row(cancel, confirm); buttons.HorizontalAlignment = HorizontalAlignment.Right; buttons.Margin = new(0, 20, 0, 0); DockPanel.SetDock(buttons, Dock.Bottom); layout.Children.Add(buttons); var heading = UI.Text(title, 21); heading.FontWeight = FontWeights.SemiBold; heading.Margin = new(0, 0, 0, 20); DockPanel.SetDock(heading, Dock.Top); layout.Children.Add(heading); layout.Children.Add(new ScrollViewer { Content = body, MaxHeight = Math.Max(200, (SystemParameters.WorkArea.Height - 280) / (LayoutPolicy.ValidScale((owner as MainWindow)?.InterfaceScale ?? 100) / 100d)), VerticalScrollBarVisibility = ScrollBarVisibility.Auto }); var scale = LayoutPolicy.ValidScale((owner as MainWindow)?.InterfaceScale ?? 100) / 100d; layout.LayoutTransform = new ScaleTransform(scale, scale); Content = layout;
    }
    public static bool Ask(Window owner, string title, string text) { Dialog dialog = new(owner, title, UI.ReadText(text, 320)); dialog.Setup(); return dialog.ShowDialog() == true; }
    public static string? Prompt(Window owner, string title, string label, string initial = "") { var input = UI.Input(initial); Dialog dialog = new(owner, title, UI.Stack(UI.Text(label), input)); dialog.Setup(); dialog.Loaded += (_, _) => { input.Focus(); input.SelectAll(); }; return dialog.ShowDialog() == true ? input.Text : null; }
    public static string[]? Select(Window owner, string title, IEnumerable<(string Key, string Label)> values)
    { var checks = values.Select(v => (v.Key, Control: UI.Check(v.Label, true))).ToArray(); Dialog dialog = new(owner, title, UI.Stack(checks.Select(c => (UIElement)c.Control).ToArray())); dialog.Setup(); return dialog.ShowDialog() == true ? checks.Where(c => c.Control.IsChecked == true).Select(c => c.Key).ToArray() : null; }
}
