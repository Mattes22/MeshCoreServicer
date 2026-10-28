using System.Net;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace MeshCore.Updates;

public sealed record UpdateFile(string Path, string Sha256, long Length, bool Executable = false);
public sealed record ReleaseManifest(int Schema, string Version, string Platform, DateTimeOffset Published,
    DateTimeOffset Expires, string EntryPoint, UpdateFile[] Files, int MinimumLauncher = 1);
public sealed record SignedRelease(string Payload, string Signature);
public sealed record UpdatePlan(ReleaseManifest Release, SignedRelease Signed, UpdateFile[] Downloads, long DownloadBytes);
public static partial class ReleaseTrust
{
    public const int LauncherVersion = 1;
    public static readonly Uri Server = new("https://servicer.zavadilmatej.cz/updates/");
    // Generated separately from Apple/firmware credentials. Private key never ships with the app.
    public const string PublicKey = "BBMWikDiL1PwuCevhgxNO0fahgcAXBtW0++bVFriz78odqEYYv82qUZcwYenLXGshXczxdz9d5DeacvWvEu+THY=";
    public static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = false, WriteIndented = true };
    [GeneratedRegex(@"^(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})$")] private static partial Regex VersionPattern();
    [GeneratedRegex(@"^[a-f0-9]{64}$")] private static partial Regex HashPattern();
    public static Version Version(string value) => value != null && VersionPattern().IsMatch(value) ? System.Version.Parse(value) : throw new InvalidDataException("Neplatná verze aktualizace.");
    public static void PathName(string path)
    {
        if (path == null || path.Length is < 1 or > 230 || path.Contains('\\') || path.Contains(':') || path.StartsWith('/') || path.Any(c => c < 32 || "<>|?*\"".Contains(c))) throw new InvalidDataException("Neplatná cesta v aktualizaci.");
        foreach (var part in path.Split('/'))
        {
            var stem = part.Split('.')[0].ToUpperInvariant();
            if (part is "" or "." or ".." || part.EndsWith(' ') || part.EndsWith('.') || stem is "CON" or "PRN" or "AUX" or "NUL" || Regex.IsMatch(stem,@"^(COM|LPT)[1-9]$")) throw new InvalidDataException("Neplatná cesta v aktualizaci.");
        }
    }
    public static string SafeFile(string root, string relative)
    {
        PathName(relative); root = System.IO.Path.GetFullPath(root); var result = System.IO.Path.GetFullPath(System.IO.Path.Combine(root,relative));
        if (!result.StartsWith(root + System.IO.Path.DirectorySeparatorChar, OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal)) throw new InvalidDataException("Cesta opouští složku aktualizace.");
        for (var cursor = new FileInfo(result) as FileSystemInfo; cursor != null; cursor = cursor is FileInfo file ? file.Directory : (cursor as DirectoryInfo)?.Parent)
        {
            if ((cursor.Exists || cursor.LinkTarget != null) && (cursor.LinkTarget != null || cursor.Attributes.HasFlag(FileAttributes.ReparsePoint))) throw new InvalidDataException("Aktualizace nesmí následovat symbolický odkaz.");
            if (cursor.FullName == root) break;
        }
        return result;
    }
    public static ECDsa Verifier(string publicKey)
    {
        var bytes = Convert.FromBase64String(publicKey); if (bytes.Length != 65 || bytes[0] != 4) throw new InvalidDataException("Neplatný veřejný klíč aktualizací.");
        return ECDsa.Create(new ECParameters { Curve = ECCurve.NamedCurves.nistP256, Q = new ECPoint { X = bytes[1..33], Y = bytes[33..65] } });
    }
    public static ReleaseManifest Verify(SignedRelease signed, string platform, DateTimeOffset now, string publicKey = PublicKey, bool installed = false)
    {
        if (signed == null || string.IsNullOrEmpty(signed.Payload) || string.IsNullOrEmpty(signed.Signature) || signed.Payload.Length > 8_000_000 || signed.Signature.Length > 200) throw new InvalidDataException("Manifest je příliš velký.");
        byte[] payload = Convert.FromBase64String(signed.Payload), signature = Convert.FromBase64String(signed.Signature);
        using var key = Verifier(publicKey);
        if (signature.Length != 64 || !key.VerifyData(payload,signature,HashAlgorithmName.SHA256,DSASignatureFormat.IeeeP1363FixedFieldConcatenation)) throw new InvalidDataException("Podpis aktualizace není platný. Nic se nezměnilo.");
        var release = JsonSerializer.Deserialize<ReleaseManifest>(payload,Json) ?? throw new InvalidDataException("Prázdný manifest.");
        _ = Version(release.Version);
        if (release.Schema != 1 || release.Platform != platform || release.Platform is not ("windows-x64" or "windows-arm64" or "linux-x64" or "linux-arm64") || release.MinimumLauncher > LauncherVersion || release.MinimumLauncher < 1) throw new InvalidDataException("Aktualizace není určená pro tuto platformu nebo vyžaduje nový instalátor.");
        if (!installed && (release.Expires <= now || release.Published > now.AddMinutes(10) || release.Expires <= release.Published)) throw new InvalidDataException("Informace o aktualizaci je zastaralá nebo má neplatný čas.");
        if (release.Files == null || release.Files.Length is < 1 or > 4096) throw new InvalidDataException("Neplatný počet souborů.");
        HashSet<string> paths = new(StringComparer.OrdinalIgnoreCase); long total = 0;
        foreach (var f in release.Files)
        {
            if (f == null || f.Sha256 == null) throw new InvalidDataException("Neplatný soubor v manifestu.");
            PathName(f.Path);
            if (f.Path.Equals(".release.json",StringComparison.OrdinalIgnoreCase) || !paths.Add(f.Path) || !HashPattern().IsMatch(f.Sha256) || f.Length is < 0 or > 268_435_456) throw new InvalidDataException("Neplatný soubor v aktualizaci.");
            total = checked(total + f.Length); if (total > 1_073_741_824) throw new InvalidDataException("Aktualizace překračuje limit velikosti.");
        }
        foreach (var path in paths) { var prefix = path; while (prefix.Contains('/')) { prefix = prefix[..prefix.LastIndexOf('/')]; if (paths.Contains(prefix)) throw new InvalidDataException("Kolize cest v manifestu."); } }
        PathName(release.EntryPoint);
        var entry = release.Files.SingleOrDefault(f => f.Path == release.EntryPoint);
        if (entry == null || !entry.Executable || entry.Length == 0) throw new InvalidDataException("Chybí spustitelný soubor aplikace.");
        return release;
    }
    public static bool Matches(string path, UpdateFile file)
    {
        if (!File.Exists(path) || new FileInfo(path).Length != file.Length) return false;
        using var stream = File.OpenRead(path); return Convert.ToHexStringLower(SHA256.HashData(stream)) == file.Sha256;
    }
    public static void VerifyTree(string root, ReleaseManifest release)
    {
        foreach (var f in release.Files) if (!Matches(SafeFile(root,f.Path),f)) throw new InvalidDataException("Kontrola souborů aktualizace selhala. Původní aplikace zůstává dostupná.");
        var allowed = release.Files.Select(f => f.Path).Append(".release.json").ToHashSet(StringComparer.Ordinal);
        Stack<string> directories = new(); directories.Push(root);
        while (directories.TryPop(out var directory))
            foreach (var item in new DirectoryInfo(directory).EnumerateFileSystemInfos()) {
                if (item.LinkTarget != null || item.Attributes.HasFlag(FileAttributes.ReparsePoint)) throw new InvalidDataException("Aktualizace nesmí obsahovat symbolický odkaz.");
                if (item is DirectoryInfo) directories.Push(item.FullName);
                else if (!allowed.Contains(System.IO.Path.GetRelativePath(root,item.FullName).Replace('\\','/'))) throw new InvalidDataException("Ve složce aktualizace je neočekávaný soubor.");
            }
    }
}

public sealed class UpdateClient : IDisposable
{
    private readonly HttpClient http;
    private readonly Uri server;
    private readonly string publicKey;
    private readonly Func<DateTimeOffset> now;
    public UpdateClient(HttpMessageHandler? handler = null, Uri? server = null, string publicKey = ReleaseTrust.PublicKey, Func<DateTimeOffset>? now = null)
    {
        this.server = server ?? ReleaseTrust.Server;
        if (this.server.Scheme != "https" || !this.server.AbsolutePath.EndsWith('/')) throw new InvalidDataException("Aktualizační server musí používat HTTPS.");
        this.publicKey = publicKey; this.now = now ?? (() => DateTimeOffset.UtcNow);
        http = new(handler ?? new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromMinutes(3) };
    }
    private async Task<byte[]> Get(Uri uri, long limit, CancellationToken token)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(3));
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(token,timeout.Token);token=linked.Token;
        using var response = await http.GetAsync(uri,HttpCompletionOption.ResponseHeadersRead,token);
        if (response.StatusCode == HttpStatusCode.NotFound) throw new InvalidDataException("Server zatím nenabízí podepsanou aktualizaci pro tuto platformu.");
        response.EnsureSuccessStatusCode();
        if (response.Content.Headers.ContentLength is { } length && length > limit) throw new InvalidDataException("Stažený soubor překračuje limit.");
        using var source = await response.Content.ReadAsStreamAsync(token); using MemoryStream target = new(); byte[] buffer = new byte[65536]; int read;
        while ((read = await source.ReadAsync(buffer,token)) > 0) { if (target.Length + read > limit) throw new InvalidDataException("Stažený soubor překračuje limit."); await target.WriteAsync(buffer.AsMemory(0,read),token); }
        return target.ToArray();
    }
    public async Task<UpdatePlan?> Check(string platform, string version, string installedRoot, CancellationToken token = default)
    {
        if (platform is not ("windows-x64" or "windows-arm64" or "linux-x64" or "linux-arm64")) throw new InvalidDataException("Nepodporovaná platforma.");
        var bytes = await Get(new(server,"stable/"+platform+".json"),8_000_000,token);
        var envelope = JsonSerializer.Deserialize<SignedRelease>(bytes,ReleaseTrust.Json) ?? throw new InvalidDataException("Prázdná informace o aktualizaci.");
        var release = ReleaseTrust.Verify(envelope,platform,now(),publicKey);
        if (ReleaseTrust.Version(release.Version) <= ReleaseTrust.Version(version)) return null;
        var downloads = await Task.Run(()=>release.Files.Where(f => !ReleaseTrust.Matches(ReleaseTrust.SafeFile(installedRoot,f.Path),f)).ToArray(),token);
        return new(release,envelope,downloads,downloads.Sum(f => f.Length));
    }
    // Called only after explicit UI confirmation. Builds a complete isolated version;
    // unchanged files are copied locally, never fetched again.
    public async Task Stage(UpdatePlan plan, string installedRoot, string stage, Action<string>? progress = null, CancellationToken token = default)
    {
        var release = ReleaseTrust.Verify(plan.Signed,plan.Release.Platform,now(),publicKey);
        if (Directory.Exists(stage)) throw new IOException("Pracovní složka aktualizace již existuje.");
        Directory.CreateDirectory(stage);
        try
        {
            int done = 0;
            foreach (var f in release.Files)
            {
                token.ThrowIfCancellationRequested(); var source = ReleaseTrust.SafeFile(installedRoot,f.Path); var destination = ReleaseTrust.SafeFile(stage,f.Path);
                Directory.CreateDirectory(System.IO.Path.GetDirectoryName(destination)!);
                if (await Task.Run(()=>ReleaseTrust.Matches(source,f),token)) await Task.Run(()=>File.Copy(source,destination),token);
                else
                {
                    if(!plan.Downloads.Any(d=>d.Path==f.Path && d.Sha256==f.Sha256 && d.Length==f.Length))throw new InvalidDataException("Místní soubory se od kontroly změnily. Proveďte novou kontrolu aktualizací a potvrďte nový plán.");
                    progress?.Invoke($"Stahuji změněný soubor {++done}/{plan.Downloads.Length}…");
                    var bytes = await Get(new(server,"objects/"+f.Sha256),f.Length,token);
                    if (bytes.LongLength != f.Length || Convert.ToHexStringLower(SHA256.HashData(bytes)) != f.Sha256) throw new InvalidDataException("Kontrolní součet staženého souboru nesouhlasí.");
                    await File.WriteAllBytesAsync(destination,bytes,token);
                }
                if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(destination,f.Executable ? UnixFileMode.UserRead|UnixFileMode.UserWrite|UnixFileMode.UserExecute : UnixFileMode.UserRead|UnixFileMode.UserWrite);
            }
            await File.WriteAllBytesAsync(System.IO.Path.Combine(stage,".release.json"),JsonSerializer.SerializeToUtf8Bytes(plan.Signed,ReleaseTrust.Json),token);
            ReleaseTrust.VerifyTree(stage,release);
        }
        catch { Directory.Delete(stage,true); throw; }
    }
    public void Dispose() => http.Dispose();
}

public sealed record VersionPointer(string Version, string Platform);
public static class VersionInstall
{
    public static string VersionDirectory(string root, string version) { _ = ReleaseTrust.Version(version); return ReleaseTrust.SafeFile(root,"versions/"+version); }
    public static void Activate(string root, string version, string platform, string publicKey = ReleaseTrust.PublicKey)
    {
        var directory = VersionDirectory(root,version);
        var signed = JsonSerializer.Deserialize<SignedRelease>(File.ReadAllBytes(System.IO.Path.Combine(directory,".release.json")),ReleaseTrust.Json) ?? throw new InvalidDataException("Chybí podpis verze.");
        var release = ReleaseTrust.Verify(signed,platform,DateTimeOffset.UtcNow,publicKey,installed:true);
        if (release.Version != version) throw new InvalidDataException("Podpis patří jiné verzi.");
        ReleaseTrust.VerifyTree(directory,release);
        var current = System.IO.Path.Combine(root,"current.json"); var temp = current+"."+Guid.NewGuid().ToString("N")+".tmp";
        if (File.Exists(current)) File.Copy(current,System.IO.Path.Combine(root,"previous.json"),true);
        File.WriteAllBytes(temp,JsonSerializer.SerializeToUtf8Bytes(new VersionPointer(version,platform),ReleaseTrust.Json));
        File.Move(temp,current,true); // Previous version is retained until confirmed startup.
    }
    public static void RestorePrevious(string root, string platform, string publicKey = ReleaseTrust.PublicKey)
    {
        var previous = System.IO.Path.Combine(root,"previous.json");
        var pointer = JsonSerializer.Deserialize<VersionPointer>(File.ReadAllBytes(previous),ReleaseTrust.Json) ?? throw new InvalidDataException();
        var directory = VersionDirectory(root,pointer.Version);
        var signed = JsonSerializer.Deserialize<SignedRelease>(File.ReadAllBytes(System.IO.Path.Combine(directory,".release.json")),ReleaseTrust.Json) ?? throw new InvalidDataException();
        var release = ReleaseTrust.Verify(signed,platform,DateTimeOffset.UtcNow,publicKey,installed:true);
        if (release.Version != pointer.Version || pointer.Platform != platform) throw new InvalidDataException();
        ReleaseTrust.VerifyTree(directory,release);
        string temp = System.IO.Path.Combine(root,"current.json."+Guid.NewGuid().ToString("N")+".tmp");
        File.Copy(previous,temp); File.Move(temp,System.IO.Path.Combine(root,"current.json"),true);
    }
    public static (string Directory, ReleaseManifest Release) Resolve(string root, string platform, string publicKey = ReleaseTrust.PublicKey)
    {
        Exception? failure = null;
        foreach (var name in new[] { "current.json","previous.json" })
        {
            try {
                var pointer = JsonSerializer.Deserialize<VersionPointer>(File.ReadAllBytes(System.IO.Path.Combine(root,name)),ReleaseTrust.Json) ?? throw new InvalidDataException("Prázdný ukazatel verze.");
                if (pointer.Platform != platform) throw new InvalidDataException("Nesprávná platforma spouštěče.");
                var directory = VersionDirectory(root,pointer.Version);
                var signed = JsonSerializer.Deserialize<SignedRelease>(File.ReadAllBytes(System.IO.Path.Combine(directory,".release.json")),ReleaseTrust.Json) ?? throw new InvalidDataException("Chybí podpis verze.");
                var release = ReleaseTrust.Verify(signed,platform,DateTimeOffset.UtcNow,publicKey,installed:true);
                if (release.Version != pointer.Version) throw new InvalidDataException("Verze nesouhlasí.");
                ReleaseTrust.VerifyTree(directory,release); return (directory,release);
            } catch (Exception ex) when (ex is IOException or JsonException or InvalidDataException or CryptographicException or FormatException) { failure = ex; }
        }
        throw new InvalidDataException("Aplikaci nelze ověřit. Použijte opravný instalátor; osobní data zůstala zachovaná.",failure);
    }
}


public enum StartupOutcome { Waiting, Confirmed, ExitedBeforeReady, RunningUnconfirmed }
public sealed class StartupAcknowledgement(DateTimeOffset started, TimeSpan timeout)
{
    public StartupOutcome Observe(bool acknowledged, bool exited, DateTimeOffset now)
        => acknowledged ? StartupOutcome.Confirmed : exited ? StartupOutcome.ExitedBeforeReady : now-started>=timeout ? StartupOutcome.RunningUnconfirmed : StartupOutcome.Waiting;
}
