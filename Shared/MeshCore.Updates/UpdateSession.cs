using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;
namespace MeshCore.Updates;
public sealed record InstallJob(string Nonce, int ParentId, long ParentStartedUtcTicks, string SourceDirectory, string TargetRoot, string StageDirectory, string Platform);
public sealed class UpdateSession : IDisposable
{
    private readonly UpdateClient client;
    private readonly string applicationDirectory, platform;
    private readonly string? installRoot, launcher;
    private readonly Func<DateTimeOffset> clock;
    private DateTimeOffset nextAutomaticCheck;
    public UpdateSession(UpdateClient? client = null, string? applicationDirectory = null, string? installRoot = null, string? launcher = null, string? platform = null, Func<DateTimeOffset>? clock = null)
    { this.client=client??new(); this.applicationDirectory=applicationDirectory??AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);this.installRoot=installRoot??InstallRoot;this.launcher=launcher??Launcher;this.platform=platform??Platform;this.clock=clock??(()=>DateTimeOffset.UtcNow); }
    public string State { get; private set; } = "Kontrola aktualizací ještě neproběhla.";
    public bool Checking { get; private set; }
    public bool Installing { get; private set; }
    public UpdatePlan? Plan { get; private set; }
    public event Action? Changed;
    public static string Platform => PlatformFor(OperatingSystem.IsWindows(), RuntimeInformation.ProcessArchitecture);
    public static string PlatformFor(bool windows, Architecture architecture) => (windows ? "windows-" : "linux-") + (architecture switch
    {
        Architecture.X64 => "x64",
        Architecture.Arm64 => "arm64",
        _ => throw new PlatformNotSupportedException("Podporované jsou pouze 64bitové procesory x64 a ARM64.")
    });
    public static string LinuxInstallRoot => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"MeshCoreServicer","Install");
    public static string? Launcher => Environment.GetEnvironmentVariable("MESHCORE_LAUNCHER");
    public static string? InstallRoot => OperatingSystem.IsWindows() ? Environment.GetEnvironmentVariable("MESHCORE_INSTALL_ROOT") : LinuxInstallRoot;
    private void Status(string text) { State = text; Changed?.Invoke(); }
    public static void MarkStartupReady()
    {
        var ack = Environment.GetEnvironmentVariable("MESHCORE_UPDATE_ACK");
        var root = InstallRoot;
        if (root != null && ack != null && Path.GetFullPath(ack).StartsWith(Path.GetFullPath(root)+Path.DirectorySeparatorChar+".staging"+Path.DirectorySeparatorChar,StringComparison.Ordinal) && Path.GetFileName(ack)=="started")
            File.WriteAllText(ReleaseTrust.SafeFile(root,Path.GetRelativePath(root,ack).Replace('\\','/')),"ready");
        Environment.SetEnvironmentVariable("MESHCORE_UPDATE_ACK",null);
    }
    public Task CheckIfDue(string version) => clock()>=nextAutomaticCheck ? Check(version,quiet:true) : Task.CompletedTask;
    public async Task Check(string version, bool quiet = false)
    {
        if (Checking || Installing) return;
        Checking = true; nextAutomaticCheck=clock().AddHours(24); Status("Ověřuji aktualizace na serveru…");
        try { Plan = await client.Check(platform,version,applicationDirectory); Status(Plan == null ? "Používáte aktuální verzi." : $"Dostupná verze {Plan.Release.Version} · změněno {Plan.Downloads.Length} souborů · {Plan.DownloadBytes/1048576.0:F1} MB ke stažení."); }
        catch (Exception ex) { Plan = null; Status(ex is InvalidDataException ? ex.Message : "Server aktualizací není dostupný nebo ověření selhalo. Aplikace zůstává beze změny."); }
        finally { Checking = false; Changed?.Invoke(); }
    }
    public async Task Install(Func<string,string,Task<bool>> confirm, Func<bool> idle, Func<Task> beforeDownload, Func<Task> quit)
    {
        if (Installing || Checking || Plan is not { } plan) return;
        if (!idle()) { Status("Před aktualizací dokončete probíhající operaci s companionem nebo repeaterem."); return; }
        var root = installRoot; var launcher = this.launcher;
        if (root == null || launcher == null || !File.Exists(launcher) || !File.Exists(Path.Combine(applicationDirectory,".release.json"))) { Status("Toto vývojové nebo starší sestavení vyžaduje první instalaci verze 0.9.0 standardním balíčkem."); return; }
        if (!await confirm("Aktualizovat a restartovat aplikaci?",$"Nová verze {plan.Release.Version}. Stáhne se jen {plan.Downloads.Length} změněných souborů ({plan.DownloadBytes/1048576.0:F1} MB). Ostatní se ověří a použijí místně. Měření se zastaví a BLE se odpojí. Profily, historie a hesla zůstanou zachované. Po instalaci se aplikace znovu spustí; správce a měření se neobnoví.")) return;
        if (!idle()) { Status("Probíhá nová operace; aktualizace se nespustila."); return; }
        Installing = true; Changed?.Invoke();
        string nonce=Guid.NewGuid().ToString("N"); string jobDirectory=ReleaseTrust.SafeFile(root,".staging/"+nonce); string stage=Path.Combine(jobDirectory,"version");
        try {
            await beforeDownload();
            await client.Stage(plan,applicationDirectory,stage,Status);
            using var parent=Process.GetCurrentProcess();
            var job=new InstallJob(nonce,parent.Id,parent.StartTime.ToUniversalTime().Ticks,applicationDirectory,Path.GetFullPath(root),stage,platform);
            var jobFile=Path.Combine(jobDirectory,"job.json"); await File.WriteAllBytesAsync(jobFile,JsonSerializer.SerializeToUtf8Bytes(job,ReleaseTrust.Json));
            var start=new ProcessStartInfo(launcher) { UseShellExecute=false };start.ArgumentList.Add("--apply-update");start.ArgumentList.Add(jobFile);
            using var helper=Process.Start(start) ?? throw new IOException("Aktualizační pomocník se nespustil.");
            var deadline=DateTimeOffset.UtcNow.AddSeconds(20);
            while (!File.Exists(Path.Combine(jobDirectory,"ready"))) { if(helper.HasExited || DateTimeOffset.UtcNow>deadline)throw new IOException("Aktualizační pomocník nepotvrdil připravenost.");await Task.Delay(100); }
            Status("Soubory ověřeny. Ukončuji aplikaci pro bezpečné přepnutí verze…"); await quit();
        }
        catch (Exception ex) { Status(ex is InvalidDataException ? ex.Message : "Aktualizace nebyla dokončena. Původní verze a místní data zůstaly zachované; nový pokus spusťte ručně."); }
        finally { Installing=false;Changed?.Invoke(); }
    }
    public void Dispose() => client.Dispose();
}
