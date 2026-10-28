// Explicit process-level test actor. No CoreBluetooth, WinRT, BlueZ or LoRa APIs.
using MeshCore.Updates;
using System.Net;
using System.Text.Json;
if(args is ["--paths"]){Console.WriteLine(UpdateSession.LinuxInstallRoot);return;}
var config=JsonSerializer.Deserialize<Config>(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"actor.json")))!;
if(config.Mode=="success"){
 UpdateSession.MarkStartupReady();File.WriteAllText(config.Result,"new-ready");await Task.Delay(2000);return;
}
if(config.Mode=="fail"){Environment.Exit(7);return;}
if(File.Exists(config.Triggered)){File.WriteAllText(config.Result,"old-restored");await Task.Delay(2000);return;}
File.WriteAllText(config.Triggered,"triggered");
var client=new UpdateClient(new LocalFeed(config.Feed,config.Requests));
using var session=new UpdateSession(client,platform:UpdateSession.Platform);
await session.Check("0.0.1");
if(session.Plan==null)throw new Exception(session.State);
await session.Install((_,_)=>Task.FromResult(true),()=>true,()=>Task.CompletedTask,()=>{Environment.Exit(0);return Task.CompletedTask;});
File.WriteAllText(config.Result,"install-error: "+session.State);
internal sealed record Config(string Mode,string Feed,string Result,string Triggered,string Requests);
internal sealed class LocalFeed(string root,string log):HttpMessageHandler
{
 protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken token)
 {
  var relative=request.RequestUri!.AbsolutePath["/updates/".Length..];ReleaseTrust.PathName(relative);
  File.AppendAllText(log,relative+"\n");var bytes=File.ReadAllBytes(ReleaseTrust.SafeFile(root,relative));
  return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK){Content=new ByteArrayContent(bytes)});
 }
}
