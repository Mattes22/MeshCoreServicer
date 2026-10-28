using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;
using MeshCore.Updates;
internal static class Program
{
    private static string Platform => UpdateSession.Platform;
    private static string Root => AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
    public static async Task<int> Main(string[] args)
    {
        try {
            if (args is ["--apply-update",var path]) { await Apply(Path.GetFullPath(path)); return 0; }
            var root=Root;
            if (!OperatingSystem.IsWindows() && File.Exists(Path.Combine(UpdateSession.LinuxInstallRoot,"current.json")))
            {
                try { var user=VersionInstall.Resolve(UpdateSession.LinuxInstallRoot,Platform); var system=VersionInstall.Resolve(root,Platform); if(ReleaseTrust.Version(user.Release.Version)>=ReleaseTrust.Version(system.Release.Version))root=UpdateSession.LinuxInstallRoot; } catch { }
            }
            var resolved=VersionInstall.Resolve(root,Platform);
            Start(resolved.Directory,resolved.Release,root,null,args); return 0;
        }
        catch (Exception ex) {
            var folder=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"MeshCoreServicer","Updates");Directory.CreateDirectory(folder);
            File.WriteAllText(Path.Combine(folder,"last-error.txt"),DateTimeOffset.UtcNow.ToString("O")+" · "+ex.GetType().Name+" · aktualizace nebo spuštění nebyly dokončeny; osobní data se nemění.");
            Console.Error.WriteLine("MeshCore Servicer nelze ověřit nebo spustit. Použijte opravný instalátor; historie a hesla se nemažou.");return 1;
        }
    }
    private static Process Start(string directory,ReleaseManifest release,string root,string? ack,IEnumerable<string>? arguments=null)
    {
        var start=new ProcessStartInfo(ReleaseTrust.SafeFile(directory,release.EntryPoint)) { UseShellExecute=false, WorkingDirectory=directory };
        start.Environment["MESHCORE_LAUNCHER"]=Environment.ProcessPath!;start.Environment["MESHCORE_INSTALL_ROOT"]=root;
        if(arguments!=null)foreach(var argument in arguments)start.ArgumentList.Add(argument);
        if(ack!=null)start.Environment["MESHCORE_UPDATE_ACK"]=ack;
        return Process.Start(start) ?? throw new IOException("Aplikace se nespustila.");
    }
    private static async Task Apply(string jobPath)
    {
        if(new FileInfo(jobPath).Length>100_000)throw new InvalidDataException();
        var job=JsonSerializer.Deserialize<InstallJob>(File.ReadAllBytes(jobPath),ReleaseTrust.Json) ?? throw new InvalidDataException();
        if(!Guid.TryParseExact(job.Nonce,"N",out _) || job.Platform!=Platform)throw new InvalidDataException();
        string root=Path.GetFullPath(job.TargetRoot);
        if(OperatingSystem.IsWindows()) { if(root!=Root)throw new InvalidDataException(); }
        else if(root!=Path.GetFullPath(UpdateSession.LinuxInstallRoot))throw new InvalidDataException();
        Directory.CreateDirectory(root);
        using var installLock=new FileStream(Path.Combine(root,"update.lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);
        var expectedJob=ReleaseTrust.SafeFile(root,".staging/"+job.Nonce+"/job.json");
        if(jobPath!=expectedJob || job.StageDirectory!=Path.Combine(Path.GetDirectoryName(expectedJob)!,"version"))throw new InvalidDataException();
        using var parent=Process.GetProcessById(job.ParentId);
        var oldSigned=JsonSerializer.Deserialize<SignedRelease>(File.ReadAllBytes(Path.Combine(job.SourceDirectory,".release.json")),ReleaseTrust.Json)!;
        var old=ReleaseTrust.Verify(oldSigned,Platform,DateTimeOffset.UtcNow,installed:true);
        if(parent.MainModule?.FileName!=ReleaseTrust.SafeFile(job.SourceDirectory,old.EntryPoint) || Math.Abs(parent.StartTime.ToUniversalTime().Ticks-job.ParentStartedUtcTicks)>TimeSpan.TicksPerSecond)throw new InvalidDataException();
        var signed=JsonSerializer.Deserialize<SignedRelease>(File.ReadAllBytes(Path.Combine(job.StageDirectory,".release.json")),ReleaseTrust.Json)!;
        var release=ReleaseTrust.Verify(signed,Platform,DateTimeOffset.UtcNow);
        if(ReleaseTrust.Version(release.Version)<=ReleaseTrust.Version(old.Version))throw new InvalidDataException("Downgrade se nepovoluje.");
        ReleaseTrust.VerifyTree(job.StageDirectory,release);
        File.WriteAllText(Path.Combine(Path.GetDirectoryName(jobPath)!,"ready"),"ready");
        using(var timeout=new CancellationTokenSource(TimeSpan.FromSeconds(90)))await parent.WaitForExitAsync(timeout.Token);
        Mutex? maintenance=null;
        if(OperatingSystem.IsWindows()) {
            maintenance=new Mutex(false,"Local\\MeshCoreServicer.Windows");
            try { if(!maintenance.WaitOne(0))throw new IOException("Probíhá jiná údržba aplikace."); }catch(AbandonedMutexException){}
        }
        // Parent and launcher are separate from immutable version folders. No executable
        // currently in use is overwritten, and the pointer switch is one atomic rename.
        string target=VersionInstall.VersionDirectory(root,release.Version);Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        if(Directory.Exists(target)) { ReleaseTrust.VerifyTree(target,release); } else Directory.Move(job.StageDirectory,target);
        if(!File.Exists(Path.Combine(root,"current.json"))) {
            var oldTarget=VersionInstall.VersionDirectory(root,old.Version);
            if(!Directory.Exists(oldTarget)) {
                string temporaryOld=Path.Combine(Path.GetDirectoryName(jobPath)!,"previous-version");Directory.CreateDirectory(temporaryOld);
                foreach(var file in old.Files) {var to=ReleaseTrust.SafeFile(temporaryOld,file.Path);Directory.CreateDirectory(Path.GetDirectoryName(to)!);File.Copy(ReleaseTrust.SafeFile(job.SourceDirectory,file.Path),to);if(!OperatingSystem.IsWindows())File.SetUnixFileMode(to,File.GetUnixFileMode(ReleaseTrust.SafeFile(job.SourceDirectory,file.Path)));}
                File.Copy(Path.Combine(job.SourceDirectory,".release.json"),Path.Combine(temporaryOld,".release.json"));
                ReleaseTrust.VerifyTree(temporaryOld,old);Directory.Move(temporaryOld,oldTarget);
            }
            VersionInstall.Activate(root,old.Version,Platform);
        }
        VersionInstall.Activate(root,release.Version,Platform);
        string ack=Path.Combine(Path.GetDirectoryName(jobPath)!,"started");
        // Register only our verified payload paths for the existing ownership-based
        // Windows uninstaller. App data and credentials never enter this list.
        if(OperatingSystem.IsWindows()) {
            var list=Path.Combine(root,"installed-files.lst");
            using var owned=new StreamWriter(list,append:true,System.Text.Encoding.Unicode);
            foreach(var file in release.Files.Select(f=>"versions/"+release.Version+"/"+f.Path).Append("versions/"+release.Version+"/.release.json").Concat(new[]{"current.json","previous.json","update.lock",".staging/"+job.Nonce+"/job.json",".staging/"+job.Nonce+"/ready",".staging/"+job.Nonce+"/started",".staging/"+job.Nonce+"/complete"}))owned.Write(file.Replace('/','\\')+"\r\n");
            using var registry=Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\MeshCoreServicer",writable:true);
            registry?.SetValue("DisplayVersion",release.Version);
        }
        // The UI owns the same mutex. Release maintenance immediately before
        // starting it; the immutable tree and active pointer are already verified.
        if(maintenance!=null){maintenance.ReleaseMutex();maintenance.Dispose();}
        Process? child=null;
        try {
            child=Start(target,release,root,ack);var startup=new StartupAcknowledgement(DateTimeOffset.UtcNow,TimeSpan.FromSeconds(30));
            StartupOutcome state;while((state=startup.Observe(File.Exists(ack),child.HasExited,DateTimeOffset.UtcNow))==StartupOutcome.Waiting)await Task.Delay(100);
            if(state==StartupOutcome.ExitedBeforeReady)throw new IOException("Nová aplikace skončila před potvrzením startu.");
            if(state==StartupOutcome.RunningUnconfirmed)throw new TimeoutException("Aplikace dosud nepotvrdila dokončení startu; běžící proces se násilně neukončuje.");
            File.WriteAllText(Path.Combine(Path.GetDirectoryName(jobPath)!,"complete"),release.Version);
        }
        catch {
            // A running app may already be using BLE. Never kill it or switch its
            // active version underneath it. Preserve both trees for manual repair.
            if(child==null || child.HasExited) {
                if(File.Exists(Path.Combine(root,"previous.json")))VersionInstall.RestorePrevious(root,Platform);
                else VersionInstall.Activate(root,old.Version,Platform);
                var previous=VersionInstall.Resolve(root,Platform);
                if(OperatingSystem.IsWindows()) {
                    using var registry=Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\MeshCoreServicer",writable:true);
                    registry?.SetValue("DisplayVersion",previous.Release.Version);
                }
                Start(previous.Directory,previous.Release,root,null);
            }
            throw;
        }
        finally {child?.Dispose();}
    }
}
