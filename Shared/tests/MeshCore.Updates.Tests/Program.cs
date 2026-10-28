using System.Net;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using MeshCore.Updates;

internal sealed class Server : HttpMessageHandler
{
    public Dictionary<string,byte[]> Files = [];
    public List<string> Requests = [];
    public Func<string,CancellationToken,Task>? Before;
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken cancellationToken)
    {
        string path=request.RequestUri!.AbsolutePath; Requests.Add(path);
        if(Before!=null)await Before(path,cancellationToken);
        return Files.TryGetValue(path,out var bytes)?new(HttpStatusCode.OK){Content=new ByteArrayContent(bytes)}:new(HttpStatusCode.NotFound);
    }
}
internal static class Program
{
    private static int passed,failed;
    private static readonly DateTimeOffset Now=new(2026,10,26,12,0,0,TimeSpan.Zero);
    private static readonly ECDsa Key=ECDsa.Create(ECCurve.NamedCurves.nistP256);
    private static string Public {get{var q=Key.ExportParameters(false).Q;return Convert.ToBase64String(new byte[]{4}.Concat(q.X!).Concat(q.Y!).ToArray());}}
    private static void Assert(bool ok){if(!ok)throw new Exception("Assertion failed");}
    private static async Task Reject(Func<Task> action){try{await action();}catch(Exception e)when(e is InvalidDataException or IOException or CryptographicException or FormatException or JsonException or OperationCanceledException){return;}throw new Exception("Expected rejection");}
    private static Task Reject(Action action)=>Reject(()=>{action();return Task.CompletedTask;});
    private static async Task Test(string name,Func<Task> action){try{await action();passed++;Console.WriteLine("PASS "+name);}catch(Exception e){failed++;Console.WriteLine("FAIL "+name+": "+e);}}
    private static Task Test(string name,Action action)=>Test(name,()=>{action();return Task.CompletedTask;});
    private static string Temp(){string p=Path.Combine(Path.GetTempPath(),"MeshCore-updates-test-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(p);return p;}
    private static byte[] Bytes(string text)=>Encoding.UTF8.GetBytes(text);
    private static UpdateFile FileEntry(string path,string content,bool executable=false)=>new(path,Convert.ToHexStringLower(SHA256.HashData(Bytes(content))),Bytes(content).Length,executable);
    private static ReleaseManifest Manifest(string version="0.9.1")=>new(1,version,"linux-x64",Now,Now.AddDays(30),"MeshCoreServicer",[FileEntry("MeshCoreServicer","new",true),FileEntry("runtime.dll","same")]);
    private static SignedRelease Sign(ReleaseManifest release){byte[] payload=JsonSerializer.SerializeToUtf8Bytes(release,ReleaseTrust.Json);return new(Convert.ToBase64String(payload),Convert.ToBase64String(Key.SignData(payload,HashAlgorithmName.SHA256,DSASignatureFormat.IeeeP1363FixedFieldConcatenation)));}
    private static Server Feed(ReleaseManifest release){var s=new Server();s.Files["/updates/stable/"+release.Platform+".json"]=JsonSerializer.SerializeToUtf8Bytes(Sign(release),ReleaseTrust.Json);foreach(var f in release.Files)s.Files["/updates/objects/"+f.Sha256]=Bytes(f.Path=="MeshCoreServicer"?"new":"same");return s;}
    private static UpdateClient Client(Server s)=>new(s,new Uri("https://updates.example/updates/"),Public,()=>Now);
    private static void Tree(string root,string version,string content="new")
    {string dir=VersionInstall.VersionDirectory(root,version);Directory.CreateDirectory(dir);File.WriteAllText(Path.Combine(dir,"MeshCoreServicer"),content);File.WriteAllText(Path.Combine(dir,"runtime.dll"),"same");var manifest=Manifest(version) with {Files=[FileEntry("MeshCoreServicer",content,true),FileEntry("runtime.dll","same")]};File.WriteAllBytes(Path.Combine(dir,".release.json"),JsonSerializer.SerializeToUtf8Bytes(Sign(manifest),ReleaseTrust.Json));}
    public static async Task<int> Main()
    {
        await Test("Platform resolver selects exact OS and process architecture",()=>{
            Assert(UpdateSession.PlatformFor(false,Architecture.X64)=="linux-x64");
            Assert(UpdateSession.PlatformFor(false,Architecture.Arm64)=="linux-arm64");
            Assert(UpdateSession.PlatformFor(true,Architecture.X64)=="windows-x64");
            Assert(UpdateSession.PlatformFor(true,Architecture.Arm64)=="windows-arm64");
            foreach(var architecture in new[]{Architecture.X86,Architecture.Arm}){
                bool rejected=false;try{UpdateSession.PlatformFor(false,architecture);}catch(PlatformNotSupportedException){rejected=true;}Assert(rejected);
            }
        });
        await Test("Signed Linux ARM64 release cannot cross architecture",async()=>{
            var arm=Manifest()with{Platform="linux-arm64"};
            Assert(ReleaseTrust.Verify(Sign(arm),"linux-arm64",Now,Public).Platform=="linux-arm64");
            await Reject(()=>ReleaseTrust.Verify(Sign(arm),"linux-x64",Now,Public));
            await Reject(()=>ReleaseTrust.Verify(Sign(Manifest()),"linux-arm64",Now,Public));
        });
        await Test("ARM64 metadata and changed files use the ARM64 signed feed",async()=>{
            string root=Temp(),stage=root+"-stage";try{
                File.WriteAllText(Path.Combine(root,"runtime.dll"),"same");
                var server=Feed(Manifest()with{Platform="linux-arm64"});using var client=Client(server);
                var plan=(await client.Check("linux-arm64","0.9.0",root))!;
                Assert(server.Requests.SequenceEqual(new[]{"/updates/stable/linux-arm64.json"})&&plan.Downloads.Length==1);
                await client.Stage(plan,root,stage);ReleaseTrust.VerifyTree(stage,plan.Release);
                Assert(server.Requests.Count==2&&server.Requests[1].StartsWith("/updates/objects/"));
            }finally{Directory.Delete(root,true);if(Directory.Exists(stage))Directory.Delete(stage,true);}
        });
        await Test("Signed manifest validates with explicit platform",()=>Assert(ReleaseTrust.Verify(Sign(Manifest()),"linux-x64",Now,Public).Version=="0.9.1"));
        await Test("Tampered signature and payload are rejected",async()=>{var s=Sign(Manifest());await Reject(()=>ReleaseTrust.Verify(s with{Payload=Convert.ToBase64String(Bytes("{}"))},"linux-x64",Now,Public));await Reject(()=>ReleaseTrust.Verify(s with{Signature=Convert.ToBase64String(new byte[64])},"linux-x64",Now,Public));});
        await Test("Wrong key cannot authorize a release",()=>Reject(()=>ReleaseTrust.Verify(Sign(Manifest()),"linux-x64",Now)));
        await Test("Null envelope fields fail closed",async()=>{await Reject(()=>ReleaseTrust.Verify(new(null!,null!),"linux-x64",Now,Public));await Reject(()=>ReleaseTrust.Version(null!));});
        await Test("Expired and future manifests rejected; installed expiry allowed",async()=>{var old=Sign(Manifest()with{Expires=Now});await Reject(()=>ReleaseTrust.Verify(old,"linux-x64",Now,Public));ReleaseTrust.Verify(old,"linux-x64",Now,Public,installed:true);await Reject(()=>ReleaseTrust.Verify(Sign(Manifest()with{Published=Now.AddHours(1)}),"linux-x64",Now,Public));});
        await Test("Wrong platform/schema/launcher version are rejected",async()=>{foreach(var m in new[]{Manifest()with{Platform="windows-x64"},Manifest()with{Schema=2},Manifest()with{MinimumLauncher=2},Manifest()with{MinimumLauncher=0}})await Reject(()=>ReleaseTrust.Verify(Sign(m),"linux-x64",Now,Public));});
        foreach(string path in new[]{"../escape","/tmp/file","a/../../file","a\\b","C:/file","a//b","a/./b","file.","NUL.txt","com1","a:x","a\nfile",".RELEASE.JSON"})
            await Test("Reject unsafe manifest path "+path.Replace('\n','?'),()=>Reject(()=>ReleaseTrust.Verify(Sign(Manifest()with{Files=[FileEntry("MeshCoreServicer","new",true),FileEntry(path,"same")]}),"linux-x64",Now,Public)));
        await Test("Duplicate case and parent/child file collisions rejected",async()=>{foreach(var paths in new[]{new[]{"a","A"},new[]{"a","a/b"}})await Reject(()=>ReleaseTrust.Verify(Sign(Manifest()with{Files=[FileEntry("MeshCoreServicer","new",true),..paths.Select(p=>FileEntry(p,"same"))]}),"linux-x64",Now,Public));});
        await Test("Missing entry point, excess file size and invalid hash rejected",async()=>{foreach(var files in new[]{new[]{FileEntry("runtime.dll","same")},new[]{FileEntry("MeshCoreServicer","new")},new[]{FileEntry("MeshCoreServicer","new",true)with{Length=268435457}},new[]{FileEntry("MeshCoreServicer","new",true)with{Sha256="bad"}}})await Reject(()=>ReleaseTrust.Verify(Sign(Manifest()with{Files=files}),"linux-x64",Now,Public));});
        await Test("Checking only fetches metadata, not application files",async()=>{var root=Temp();try{using var client=Client(Feed(Manifest()));var server=Feed(Manifest());using var c=Client(server);var plan=await c.Check("linux-x64","0.9.0",root);Assert(plan!.Downloads.Length==2);Assert(server.Requests.SequenceEqual(new[]{"/updates/stable/linux-x64.json"}));}finally{Directory.Delete(root,true);}});
        await Test("No downgrade or same-version installation offered",async()=>{var root=Temp();try{var server=Feed(Manifest("0.9.0"));using var c=Client(server);Assert(await c.Check("linux-x64","0.9.0",root)==null);Assert(await c.Check("linux-x64","0.9.1",root)==null);}finally{Directory.Delete(root,true);}});
        await Test("Only changed files downloaded; unchanged runtime copied locally",async()=>{string root=Temp(),stage=root+"-stage";try{File.WriteAllText(Path.Combine(root,"runtime.dll"),"same");File.WriteAllText(Path.Combine(root,"MeshCoreServicer"),"old");var server=Feed(Manifest());using var c=Client(server);var plan=await c.Check("linux-x64","0.9.0",root);Assert(plan!.Downloads.Length==1&&plan.DownloadBytes==3);await c.Stage(plan,root,stage);Assert(server.Requests.Count==2&&server.Requests[1].EndsWith(plan.Downloads[0].Sha256));Assert(File.ReadAllText(Path.Combine(stage,"MeshCoreServicer"))=="new");Assert(File.ReadAllText(Path.Combine(root,"MeshCoreServicer"))=="old");ReleaseTrust.VerifyTree(stage,plan.Release);}finally{Directory.Delete(root,true);if(Directory.Exists(stage))Directory.Delete(stage,true);}});
        await Test("Corrupt download removes stage and preserves installed files",async()=>{var root=Temp();string stage=root+"-stage";try{File.WriteAllText(Path.Combine(root,"MeshCoreServicer"),"old");var server=Feed(Manifest());server.Files["/updates/objects/"+Manifest().Files[0].Sha256]=Bytes("bad");using var c=Client(server);var plan=(await c.Check("linux-x64","0.9.0",root))!;await Reject(()=>c.Stage(plan,root,stage));Assert(!Directory.Exists(stage)&&File.ReadAllText(Path.Combine(root,"MeshCoreServicer"))=="old");}finally{Directory.Delete(root,true);}});
        await Test("Cancellation discards partial staging without changing current version",async()=>{var root=Temp();string stage=root+"-stage";try{using var cancel=new CancellationTokenSource();var server=Feed(Manifest());using var c=Client(server);var plan=(await c.Check("linux-x64","0.9.0",root))!;server.Before=(path,ct)=>{cancel.Cancel();ct.ThrowIfCancellationRequested();return Task.CompletedTask;};await Reject(()=>c.Stage(plan,root,stage,token:cancel.Token));Assert(!Directory.Exists(stage));}finally{Directory.Delete(root,true);}});
        await Test("Extra files and symlink directories are not accepted",async()=>{var root=Temp();try{Tree(root,"0.9.0");string dir=VersionInstall.VersionDirectory(root,"0.9.0");var release=Manifest("0.9.0");File.WriteAllText(Path.Combine(dir,"extra"),"unknown");await Reject(()=>ReleaseTrust.VerifyTree(dir,release));File.Delete(Path.Combine(dir,"extra"));if(!OperatingSystem.IsWindows()){Directory.CreateSymbolicLink(Path.Combine(dir,"escape"),root);await Reject(()=>ReleaseTrust.VerifyTree(dir,release));Directory.Delete(Path.Combine(dir,"escape"));}}finally{Directory.Delete(root,true);}});
        await Test("SafeFile refuses links even when pointed outside install root",async()=>{if(OperatingSystem.IsWindows())return;var root=Temp();try{Directory.CreateSymbolicLink(Path.Combine(root,"link"),Path.GetTempPath());await Reject(()=>ReleaseTrust.SafeFile(root,"link/unknown"));}finally{Directory.Delete(root,true);}});
        await Test("Atomic activation retains old version and verified rollback",()=>{var root=Temp();try{Tree(root,"0.9.0","old");Tree(root,"0.9.1");VersionInstall.Activate(root,"0.9.0","linux-x64",Public);VersionInstall.Activate(root,"0.9.1","linux-x64",Public);Assert(VersionInstall.Resolve(root,"linux-x64",Public).Release.Version=="0.9.1");VersionInstall.RestorePrevious(root,"linux-x64",Public);Assert(VersionInstall.Resolve(root,"linux-x64",Public).Release.Version=="0.9.0");Assert(Directory.Exists(VersionInstall.VersionDirectory(root,"0.9.1")));}finally{Directory.Delete(root,true);}});
        await Test("Corrupt/null current pointer falls back to verified previous version",()=>{var root=Temp();try{Tree(root,"0.9.0");Tree(root,"0.9.1");VersionInstall.Activate(root,"0.9.0","linux-x64",Public);VersionInstall.Activate(root,"0.9.1","linux-x64",Public);File.WriteAllText(Path.Combine(root,"current.json"),"null");Assert(VersionInstall.Resolve(root,"linux-x64",Public).Release.Version=="0.9.0");}finally{Directory.Delete(root,true);}});
        await Test("Corrupt new executable cannot become the active version",async()=>{var root=Temp();try{Tree(root,"0.9.0");Tree(root,"0.9.1");VersionInstall.Activate(root,"0.9.0","linux-x64",Public);File.WriteAllText(Path.Combine(VersionInstall.VersionDirectory(root,"0.9.1"),"MeshCoreServicer"),"broken");await Reject(()=>VersionInstall.Activate(root,"0.9.1","linux-x64",Public));Assert(VersionInstall.Resolve(root,"linux-x64",Public).Release.Version=="0.9.0");}finally{Directory.Delete(root,true);}});
        await Test("Declining consent never stages files or stops companion",async()=>{string root=Temp(),install=Temp();try{File.WriteAllText(Path.Combine(root,".release.json"),"{}");var exe=Path.Combine(install,"launcher");File.WriteAllText(exe,"");var server=Feed(Manifest());using var session=new UpdateSession(Client(server),root,install,exe,"linux-x64");await session.Check("0.9.0");bool stopped=false;await session.Install((_,_)=>Task.FromResult(false),()=>true,()=>{stopped=true;return Task.CompletedTask;},()=>throw new Exception("Must not quit"));Assert(!stopped&&!Directory.Exists(Path.Combine(install,".staging"))&&server.Requests.Count==1);}finally{Directory.Delete(root,true);Directory.Delete(install,true);}});
        await Test("Busy service blocks consent and queued update work",async()=>{string root=Temp();try{var server=Feed(Manifest());using var session=new UpdateSession(Client(server),root,root,Path.Combine(root,"launcher"),"linux-x64");await session.Check("0.9.0");await session.Install((_,_)=>throw new Exception("Must not prompt"),()=>false,()=>throw new Exception(),()=>throw new Exception());Assert(!session.Installing&&server.Requests.Count==1);}finally{Directory.Delete(root,true);}});
        await Test("Automatic checks are metadata-only and at most once per 24h",async()=>{var root=Temp();try{var server=Feed(Manifest());var time=Now;using var session=new UpdateSession(Client(server),root,root,platform:"linux-x64",clock:()=>time);await session.CheckIfDue("0.9.0");time+=TimeSpan.FromHours(23);await session.CheckIfDue("0.9.0");Assert(server.Requests.Count==1);time+=TimeSpan.FromHours(1);await session.CheckIfDue("0.9.0");Assert(server.Requests.Count==2&&server.Requests.All(p=>p.EndsWith(".json")));}finally{Directory.Delete(root,true);}});
        await Test("Startup waits for ACK; an early exit permits rollback",()=>{var startup=new StartupAcknowledgement(Now,TimeSpan.FromSeconds(30));Assert(startup.Observe(false,false,Now.AddSeconds(29))==StartupOutcome.Waiting);Assert(startup.Observe(false,true,Now.AddSeconds(1))==StartupOutcome.ExitedBeforeReady);Assert(startup.Observe(true,false,Now.AddSeconds(1))==StartupOutcome.Confirmed);});
        await Test("A still-running unconfirmed app must never be killed for rollback",()=>{var startup=new StartupAcknowledgement(Now,TimeSpan.FromSeconds(30));Assert(startup.Observe(false,false,Now.AddSeconds(30))==StartupOutcome.RunningUnconfirmed);Assert(startup.Observe(true,false,Now.AddSeconds(31))==StartupOutcome.Confirmed);});
        await Test("Local changes after consent cannot silently increase approved downloads",async()=>{string root=Temp(),stage=root+"-stage";try{File.WriteAllText(Path.Combine(root,"MeshCoreServicer"),"new");File.WriteAllText(Path.Combine(root,"runtime.dll"),"same");var server=Feed(Manifest());using var c=Client(server);var plan=(await c.Check("linux-x64","0.9.0",root))!;Assert(plan.Downloads.Length==0);File.WriteAllText(Path.Combine(root,"runtime.dll"),"changed");await Reject(()=>c.Stage(plan,root,stage));Assert(server.Requests.Count==1&&!Directory.Exists(stage));}finally{Directory.Delete(root,true);}});
        Console.WriteLine($"Updates: {passed} passed, {failed} failed. No actual network, BLE or LoRa.");return failed==0?0:1;
    }
}
