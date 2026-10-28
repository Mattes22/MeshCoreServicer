using System;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace MeshCore.Windows;
public sealed partial class MainWindow
{
    private Grid shell = null!;
    internal int InterfaceScale => LayoutPolicy.ValidScale(model.Library.InterfaceScale);
    private void ApplyInterfaceScale() { double scale = InterfaceScale / 100d; shell.LayoutTransform = new ScaleTransform(scale, scale); }
    private void BuildShell()
    {
        Grid root = shell = new(); root.ColumnDefinitions.Add(new() { Width = new(260) }); root.ColumnDefinitions.Add(new() { Width = new(1, GridUnitType.Star) });
        DockPanel sidebar = new(); var sideSurface = new Border { Child = sidebar, BorderThickness = new(0, 0, 1, 0) }; sideSurface.SetResourceReference(Border.BackgroundProperty, "SidebarBackground"); sideSurface.SetResourceReference(Border.BorderBrushProperty, "AppBorder"); root.Children.Add(sideSurface);
        var brandName = UI.Text("MeshCore", 21); brandName.FontWeight = FontWeights.Bold; var brandSub = UI.Secondary("S E R V I C E R", 9); brandSub.FontWeight = FontWeights.Bold;
        var brand = new StackPanel { Orientation = Orientation.Horizontal, Margin = new(22, 25, 10, 24) }; var mark = UI.MeshMark(); mark.Margin = new(0, 0, 13, 0); brand.Children.Add(mark); brand.Children.Add(UI.Stack(brandName, brandSub)); DockPanel.SetDock(brand, Dock.Top); sidebar.Children.Add(brand);
        var label = UI.Secondary("PRACOVNÍ PROSTOR", 9); label.FontWeight = FontWeights.SemiBold; label.Margin = new(22, 0, 0, 8); DockPanel.SetDock(label, Dock.Top); sidebar.Children.Add(label);
        var footerName = UI.Stack(companionName, companionHint); companionName.Margin = new(0, 0, 0, 3); companionHint.Margin = new(0);
        var companion = UI.Button("", () => { navigation.SelectedIndex = 0; return Task.CompletedTask; }); companion.SetResourceReference(StyleProperty, "PlainButton"); companion.Content = UI.Row(UI.Icon("connection", 16), footerName); companion.HorizontalContentAlignment = HorizontalAlignment.Left; companion.Padding = new(18, 16, 12, 16); companion.Margin = new(0); companion.ToolTip = "Připojení companionu"; System.Windows.Automation.AutomationProperties.SetName(companion, "Připojení companionu");
        var footer = UI.Stack(UI.Divider(), companion); DockPanel.SetDock(footer, Dock.Bottom); sidebar.Children.Add(footer);
        var nodeLabel = UI.Secondary("VYBRANÝ REPEATER", 9); nodeLabel.FontWeight = FontWeights.SemiBold;
        var node = UI.Row(UI.Avatar("repeater", 30), repeaterName); repeaterName.VerticalAlignment = VerticalAlignment.Center;
        repeaterSummary = UI.Card(UI.Stack(nodeLabel, node, repeaterAccess), 15); repeaterSummary.Margin = new(12); repeaterSummary.SetResourceReference(Border.BackgroundProperty, "SubtleSurface"); repeaterSummary.Visibility = Visibility.Collapsed; DockPanel.SetDock(repeaterSummary, Dock.Bottom); sidebar.Children.Add(repeaterSummary);
        var names = new[] { "Připojení", "Kontakty", "Zprávy", "Správa repeateru", "Konzole", "Diagnostika" }; var symbols = new[] { "connection", "contacts", "messages", "repeater", "console", "diagnostics" };
        for (int i = 0; i < names.Length; i++)
        {
            DockPanel line = new() { LastChildFill = true }; var count = UI.Secondary("", 11); count.Margin = new(8, 0, 0, 0); count.VerticalAlignment = VerticalAlignment.Center; navigationCounts[i] = count; DockPanel.SetDock(count, Dock.Right); line.Children.Add(count);
            var icon = UI.Icon(symbols[i], 17); icon.Margin = new(0, 0, 10, 0); icon.SetBinding(System.Windows.Shapes.Shape.StrokeProperty, new System.Windows.Data.Binding("Foreground") { RelativeSource = new(System.Windows.Data.RelativeSourceMode.FindAncestor, typeof(ListBoxItem), 1) }); line.Children.Add(icon); var name = UI.Text(names[i]); name.Margin = new(0); name.VerticalAlignment = VerticalAlignment.Center; line.Children.Add(name);
            navigation.Items.Add(new ListBoxItem { Content = line, Padding = new(12, 10, 12, 10), MinHeight = 38, ToolTip = $"Ctrl+{i + 1} · {names[i]}" });
        }
        navigation.Items.Add(new ListBoxItem { Visibility = Visibility.Collapsed }); navigation.SelectionChanged += (_, _) => Navigate(); sidebar.Children.Add(new ScrollViewer { Content = navigation, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled });
        DockPanel workspace = new(); Grid.SetColumn(workspace, 1); root.Children.Add(workspace);
        Grid toolbar = new() { Height = 58, Margin = new(20, 0, 12, 0) }; toolbar.ColumnDefinitions.Add(new() { Width = new(1, GridUnitType.Star) }); toolbar.ColumnDefinitions.Add(new() { Width = GridLength.Auto }); toolbar.ColumnDefinitions.Add(new() { Width = GridLength.Auto }); sectionTitle.VerticalAlignment = VerticalAlignment.Center; sectionTitle.Margin = new(0); toolbar.Children.Add(sectionTitle);
        header.Margin = new(0); header.TextWrapping = TextWrapping.NoWrap; header.TextTrimming = TextTrimming.CharacterEllipsis; header.SetResourceReference(TextBlock.ForegroundProperty, "SecondaryText"); var badge = new Border { Child = header, CornerRadius = new(15), Padding = new(12, 6, 12, 6), MaxWidth = 380, VerticalAlignment = VerticalAlignment.Center }; badge.SetResourceReference(Border.BackgroundProperty, "SubtleSurface"); Grid.SetColumn(badge, 1); toolbar.Children.Add(badge);
        Button Tool(string symbol, string title, Func<Task> action)
        {
            var b = UI.Button("", () => Invoke(action)); var icon = UI.Icon(symbol, 22); icon.SetBinding(System.Windows.Shapes.Shape.StrokeProperty, new System.Windows.Data.Binding("Foreground") { Source = b });
            b.Tag = "ToolbarIcon"; b.Content = icon; b.ToolTip = title; System.Windows.Automation.AutomationProperties.SetName(b, title); b.SetResourceReference(StyleProperty, "PlainButton");
            b.Margin = new(4, 0, 0, 0); b.Padding = new(8); b.Width = b.Height = 42; return b;
        }

        disconnectButton = Tool("logout", "Odpojit companion", () => { wantedAddress = null; StopConnection(); return Task.CompletedTask; });
        var tools = UI.Row(disconnectButton, Tool("settings", "Nastavení · Ctrl+,", () => { navigation.SelectedIndex = 6; return Task.CompletedTask; }), Tool("diagnostics", "Diagnostika", () => { navigation.SelectedIndex = 5; return Task.CompletedTask; })); tools.HorizontalAlignment = HorizontalAlignment.Right; tools.VerticalAlignment = VerticalAlignment.Center; tools.Margin = new(0); Grid.SetColumn(tools, 2); toolbar.Children.Add(tools);
        var toolbarBorder = new Border { Child = toolbar, BorderThickness = new(0, 0, 0, 1) }; toolbarBorder.SetResourceReference(Border.BorderBrushProperty, "AppBorder"); DockPanel.SetDock(toolbarBorder, Dock.Top); workspace.Children.Add(toolbarBorder);
        errorBanner = UI.Banner("Operace nebyla dokončena", "", true); errorBanner.Child = UI.Stack(UI.Text("Operace nebyla dokončena"), error); errorBanner.Margin = new(20, 16, 20, 0); errorBanner.Visibility = Visibility.Collapsed; DockPanel.SetDock(errorBanner, Dock.Top); workspace.Children.Add(errorBanner);
        DockPanel bar = new() { Margin = new(20, 0, 20, 0), Height = 42 }; var applicationVersion = UI.Secondary($"Verze {ApplicationVersion}", 13); applicationVersion.Name = "ApplicationVersion"; applicationVersion.VerticalAlignment = VerticalAlignment.Center; applicationVersion.Margin = new(16, 0, 0, 0); DockPanel.SetDock(applicationVersion, Dock.Right); bar.Children.Add(applicationVersion); connectionRoute = UI.Secondary("BLE → companion · LoRa → repeater", 10); var route = connectionRoute; route.FontFamily = UI.Mono; route.Margin = new(16, 0, 0, 0); route.VerticalAlignment = VerticalAlignment.Center; DockPanel.SetDock(route, Dock.Right); bar.Children.Add(route); bar.Children.Add(progress); status.Margin = new(0); status.TextTrimming = TextTrimming.CharacterEllipsis; status.TextWrapping = TextWrapping.NoWrap; status.VerticalAlignment = VerticalAlignment.Center; bar.Children.Add(status);
        var bottom = new Border { Child = bar, BorderThickness = new(0, 1, 0, 0) }; bottom.SetResourceReference(Border.BorderBrushProperty, "AppBorder"); DockPanel.SetDock(bottom, Dock.Bottom); workspace.Children.Add(bottom); workspace.Children.Add(page); Content = root;
        void Adapt()
        {
            bool compact = LayoutPolicy.Compact(root.ActualWidth);
            root.ColumnDefinitions[0].Width = new(compact ? 76 : 260);
            brandName.Visibility = brandSub.Visibility = label.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
            brand.Margin = compact ? new(20, 18, 0, 18) : new(22, 25, 10, 24);
            companionName.Visibility = companionHint.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
            repeaterSummary.Visibility = compact || root.ActualHeight < 700 || model.Node == null ? Visibility.Collapsed : Visibility.Visible;
            sectionTitle.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
            route.Visibility = root.ActualWidth < 1280 ? Visibility.Collapsed : Visibility.Visible;
            badge.MaxWidth = Math.Max(160, Math.Min(440, root.ActualWidth - (compact ? 76 : 260) - 200));
            for (int i = 0; i < 6; i++)
            {
                var item = (ListBoxItem)navigation.Items[i]; var line = (DockPanel)item.Content;
                line.Children[0].Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
                line.Children[2].Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
                ((FrameworkElement)line.Children[1]).Margin = compact ? new(0) : new(0, 0, 10, 0);
                item.HorizontalContentAlignment = compact ? HorizontalAlignment.Center : HorizontalAlignment.Stretch;
            }
        }
        root.SizeChanged += (_, _) => Adapt();

    }
}
