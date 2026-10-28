using Avalonia;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Styling;
using Avalonia.Threading;
using Avalonia.VisualTree;
using MeshCore.Linux;
using MeshCore.Core;
internal static class Program
{
    [STAThread] public static int Main(string[] args)
    {
        int passed=0;string root=Path.Combine(Path.GetTempPath(),"MeshCore-linux-ui-test-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
        try {
            AppBuilder.Configure<App>().UseSkia().UseHeadless(new AvaloniaHeadlessPlatformOptions{UseHeadlessDrawing=false}).SetupWithoutStarting();
            var window=new MainWindow(verification:true,localData:root);window.Show();
            foreach(var theme in new[]{ThemeVariant.Light,ThemeVariant.Dark})foreach(var size in new[]{new Size(800,600),new Size(1280,880),new Size(1920,1080)})foreach(int section in Enumerable.Range(0,7)) {
                Application.Current!.RequestedThemeVariant=theme;window.Width=size.Width;window.Height=size.Height;window.NavigateForVerification(section);Dispatcher.UIThread.RunJobs();
                using var frame=window.CaptureRenderedFrame()??throw new Exception("No rendered UI");
                if(window.GetVisualDescendants().OfType<TextBlock>().Any(t=>!double.IsFinite(t.Bounds.Width)||!double.IsFinite(t.Bounds.Height)))throw new Exception("Invalid layout bounds");
                if(args.Length==1&&size.Width==1280&&section is 0 or 3 or 4 or 6){Directory.CreateDirectory(args[0]);frame.Save(Path.Combine(args[0],$"linux-{theme}-{section}.png"),new Avalonia.Media.Imaging.PngBitmapEncoderOptions());}
                passed++;Console.WriteLine($"PASS native UI {theme} {size.Width}×{size.Height} page {section}");
            }
            window.NavigateForVerification(6);Dispatcher.UIThread.RunJobs();
            var save=window.GetVisualDescendants().OfType<Button>().Single(b=>b.Content as string=="Uložit nastavení");
            if(save.IsEnabled)throw new Exception("Saving must be blocked until this instance owns and loads local storage");passed++;
            var ble=new BlueZTransport();var controller=new Controller(ble,new TestCredentials());string report=controller.BleDiagnosticReport();if(!report.Contains("linux-bluez-dbus-1")||report.Contains("windows-ble-enumerate"))throw new Exception("Incorrect transport identifier");ble.Dispose();passed++;
            if(Directory.GetFiles(root).Length!=0)throw new Exception("Verification started persistence, BLE or update routines");passed++;
            var usbWindow=new MainWindow(verification:true,localData:root);usbWindow.Content=new ScrollViewer{Content=usbWindow.CreateUsbWorkspaceForVerification()};usbWindow.Show();
            foreach(var theme in new[]{ThemeVariant.Light,ThemeVariant.Dark})foreach(var size in new[]{new Size(800,600),new Size(1280,880),new Size(1920,1080)}){
                Application.Current!.RequestedThemeVariant=theme;usbWindow.Width=size.Width;usbWindow.Height=size.Height;Dispatcher.UIThread.RunJobs();
                using var frame=usbWindow.CaptureRenderedFrame()??throw new Exception("No USB workspace rendering");
                if(usbWindow.GetVisualDescendants().OfType<Button>().Any(b=>b.Content as string=="Odeslat USB příkaz…"&&b.IsEnabled))throw new Exception("Disconnected USB command must be disabled");
                passed++;Console.WriteLine($"PASS native USB workspace {theme} {size.Width}×{size.Height}");
            }usbWindow.Close();
            window.Close();Console.WriteLine($"Linux: {passed} checks passed; headless rendering only, no BlueZ/BLE/LoRa.");return 0;
        } catch(Exception e){Console.Error.WriteLine(e);return 1;}finally{Directory.Delete(root,true);}
    }
    private sealed class TestCredentials:ICredentialStore { public string? Load(string k)=>null;public void Save(string k,string p)=>throw new Exception();public void Delete(string k)=>throw new Exception(); }
}
