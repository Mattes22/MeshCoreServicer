using System;
using System.Threading;
using System.Windows;

namespace MeshCore.Windows;
public static class Program
{
    [STAThread] public static void Main(string[] args)
    {
        if (args.Length > 0 && args[0] == "--verify-ui") { PresentationVerification.Run(args.Length > 1 ? args[1] : null); return; }
        using Mutex instance = new(true, "Local\\MeshCoreServicer.Windows", out bool first);
        if (!first) { MessageBox.Show("MeshCore Servicer už běží. Otevřete jej z oznamovací oblasti Windows.", "MeshCore Servicer"); return; }
        Application app = new() { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.DispatcherUnhandledException += (_, e) => { MessageBox.Show("Operace aplikace selhala. Zkontrolujte spojení a před opakováním změny znovu načtěte stav zařízení.", "MeshCore Servicer"); e.Handled = true; };
        app.Run(new MainWindow());
    }
}
