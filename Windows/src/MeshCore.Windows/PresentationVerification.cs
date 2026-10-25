using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace MeshCore.Windows;
// Explicit Windows-only UI verification. It never loads profiles or starts BLE.
internal static class PresentationVerification
{
    public static void Run(string? folder)
    {
        string output = Path.GetFullPath(folder ?? Path.Combine(Path.GetTempPath(), "MeshCoreServicer-UI-" + Guid.NewGuid())); Directory.CreateDirectory(output);
        Application application = new() { ShutdownMode = ShutdownMode.OnExplicitShutdown }; MainWindow? window = null;
        try
        {
            window = new MainWindow(verification: true) { Width = 1280, Height = 860, ShowInTaskbar = false, WindowStartupLocation = WindowStartupLocation.Manual, Left = -20000, Top = -20000 };
            window.Show(); var files = window.VerifyPresentation(output); window.FinishPresentationVerification();
            File.WriteAllText(Path.Combine(output, "result.json"), JsonSerializer.Serialize(new { Version = MeshCore.Core.Controller.Version, Result = "Passed", NativeWpf = true, PhysicalBleTest = false, ProfilesLoaded = false, RealMonitorDpiTest = false, LayoutAssertions = true, Files = files }, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (Exception exception)
        {
            window?.FinishPresentationVerification(); Environment.ExitCode = 1;
            File.WriteAllText(Path.Combine(output, "result.json"), JsonSerializer.Serialize(new { Result = "Failed", PhysicalBleTest = false, Error = exception.ToString() }, new JsonSerializerOptions { WriteIndented = true }));
        }
        finally { application.Shutdown(Environment.ExitCode); }
    }
}
public sealed partial class MainWindow
{
    internal List<string> VerifyPresentation(string output)
    {
        var files = new List<string>();
        foreach (var (theme, name) in new[] { ("Světlý", "light"), ("Tmavý", "dark") })
        {
            UI.Theme(theme); VerifyLayoutPrimitives();
            foreach (var (label, width, height, scale) in new[] { ("small", 760, 540, 100), ("laptop", 1024, 720, 115), ("desktop", 1440, 960, 100), ("large", 1920, 1080, 130), ("zoom", 900, 650, 150) })
            {
                Width = width; Height = height; model.Library.InterfaceScale = scale; ApplyInterfaceScale();
                for (int section = 0; section < 7; section++)
                {
                    navigation.SelectedIndex = section; header.Text = "OVĚŘENÍ UI · BEZ DAT · BEZ BLE";
                    var visited = new HashSet<DependencyObject>();
                    void Apply(DependencyObject element)
                    {
                        if (!visited.Add(element)) return;
                        if (element is FrameworkElement framework) framework.ApplyTemplate();
                        foreach (var child in LogicalTreeHelper.GetChildren(element)) if (child is DependencyObject dependency) Apply(dependency);
                    }
                    Apply(this); UpdateLayout(); Dispatcher.Invoke(() => { }, DispatcherPriority.Render); UpdateLayout();
                    AssertToolbarIcons(shell);
                    var content = (FrameworkElement)Content;
                    // Render the actual client area, preserving its layout transform. Bitmap
                    // density is export metadata, not a simulation of a real monitor DPI change.
                    double zoom = InterfaceScale / 100d; var actual = new Size(Math.Ceiling(content.ActualWidth * zoom), Math.Ceiling(content.ActualHeight * zoom));
                    DrawingVisual drawing = new(); using (var dc = drawing.RenderOpen()) dc.DrawRectangle(new VisualBrush(content) { Stretch = Stretch.Fill }, null, new Rect(new Point(), actual));
                    RenderTargetBitmap bitmap = new((int)actual.Width, (int)actual.Height, 96, 96, PixelFormats.Pbgra32); bitmap.Render(drawing); PngBitmapEncoder encoder = new(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                    var file = $"windows-{section + 1}-{name}-{label}-{scale}.png"; using var stream = File.Create(Path.Combine(output, file)); encoder.Save(stream); files.Add(file);
                }
            }
        }

        return files;
    }
    private static void AssertToolbarIcons(DependencyObject element)
    {
        if (element is Button { Tag: "ToolbarIcon", Content: System.Windows.Shapes.Path icon } button)
        {
            double slot = button.ActualWidth - button.Padding.Left - button.Padding.Right - button.BorderThickness.Left - button.BorderThickness.Right;
            if (slot < icon.Width || icon.ActualWidth < 20 || icon.ActualHeight < 20) throw new InvalidOperationException("Toolbar icon is clipped by button padding.");
        }
        for (int i = 0; i < VisualTreeHelper.GetChildrenCount(element); i++) AssertToolbarIcons(VisualTreeHelper.GetChild(element, i));
    }
    private static void VerifyLayoutPrimitives()
    {
        foreach (double width in new[] { 350d, 496, 740, 1008, 1500 })
        {
            var columns = UI.Columns(Enumerable.Range(0, 4).Select(i => (UIElement)UI.Card(UI.Text("Čitelný text a dlouhý český popisek " + i))).ToArray());
            columns.Measure(new Size(width, double.PositiveInfinity)); columns.Arrange(new Rect(0, 0, width, columns.DesiredSize.Height)); columns.UpdateLayout();
            if (columns.ColumnDefinitions.Count != LayoutPolicy.Columns(width, 240, 4)) throw new InvalidOperationException("Responsive column count mismatch.");
            foreach (FrameworkElement child in columns.Children)
            {
                var bounds = child.TransformToAncestor(columns).TransformBounds(new Rect(child.RenderSize));
                if (bounds.Left < -.5 || bounds.Right > width + .5) throw new InvalidOperationException("Card extends beyond the workspace.");
            }
        }
        var heading = UI.Heading("Kontrola", "Dlouhý český nadpis", "Podrobný popis", UI.Combo(new[] { "Výběr uzlu" }));
        heading.Measure(new Size(420, double.PositiveInfinity)); heading.Arrange(new Rect(0, 0, 420, heading.DesiredSize.Height));
        if (Grid.GetRow(heading.Children[1]) != 1) throw new InvalidOperationException("Heading actions must wrap below the title.");
    }
    internal void FinishPresentationVerification() { exiting = true; timer.Stop(); ble.Dispose(); Close(); }
}
