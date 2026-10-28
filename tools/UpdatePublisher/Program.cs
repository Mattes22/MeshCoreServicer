using System.Security.Cryptography;
using System.Text.Json;
using MeshCore.Updates;
if (args.Length == 3 && args[0] == "verify") {
 var folder=Path.GetFullPath(args[1]);var signed=JsonSerializer.Deserialize<SignedRelease>(File.ReadAllBytes(Path.Combine(folder,".release.json")),ReleaseTrust.Json)??throw new InvalidDataException();
 var release=ReleaseTrust.Verify(signed,args[2],DateTimeOffset.UtcNow,installed:true);ReleaseTrust.VerifyTree(folder,release);Console.WriteLine($"Verified {release.Platform} {release.Version}: {release.Files.Length} files.");return;
}
if (args.Length == 2 && args[0] == "keygen") {
 var path = Path.GetFullPath(args[1]); if (File.Exists(path)) throw new IOException("Klíč již existuje a nebude přepsán.");
 Directory.CreateDirectory(Path.GetDirectoryName(path)!); using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
 File.WriteAllBytes(path,key.ExportPkcs8PrivateKey()); if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(path,UnixFileMode.UserRead|UnixFileMode.UserWrite);
 var q=key.ExportParameters(false).Q; Console.WriteLine(Convert.ToBase64String(new byte[] {4}.Concat(q.X!).Concat(q.Y!).ToArray())); return;
}
if (args.Length == 6 && args[0] == "publish") {
 var folder=Path.GetFullPath(args[1]); var platform=args[2]; var version=args[3]; var destination=Path.GetFullPath(args[4]);
 using var key=ECDsa.Create(); key.ImportPkcs8PrivateKey(File.ReadAllBytes(args[5]),out _);
 var q=key.ExportParameters(false).Q; var pub=Convert.ToBase64String(new byte[]{4}.Concat(q.X!).Concat(q.Y!).ToArray());
 if(pub != ReleaseTrust.PublicKey) throw new InvalidDataException("Podepisovací klíč neodpovídá klíči této aplikace.");
 List<UpdateFile> files=[];
 foreach(var path in Directory.GetFiles(folder,"*",SearchOption.AllDirectories).Order()) {
  var name=Path.GetRelativePath(folder,path).Replace('\\','/'); if(name==".release.json")continue;
  var safe=ReleaseTrust.SafeFile(folder,name); using var source=File.OpenRead(safe);
  files.Add(new(name,Convert.ToHexStringLower(SHA256.HashData(source)),source.Length,platform.StartsWith("windows") ? name.EndsWith(".exe") : name=="MeshCoreServicer" || name.EndsWith(".so")));
 }
 var manifest=new ReleaseManifest(1,version,platform,DateTimeOffset.UtcNow,DateTimeOffset.UtcNow.AddDays(90),platform.StartsWith("windows")?"MeshCoreServicer.exe":"MeshCoreServicer",files.ToArray());
 var payload=JsonSerializer.SerializeToUtf8Bytes(manifest,ReleaseTrust.Json);
 var signed=new SignedRelease(Convert.ToBase64String(payload),Convert.ToBase64String(key.SignData(payload,HashAlgorithmName.SHA256,DSASignatureFormat.IeeeP1363FixedFieldConcatenation)));
 _=ReleaseTrust.Verify(signed,platform,DateTimeOffset.UtcNow,pub);
 Directory.CreateDirectory(Path.Combine(destination,"objects"));Directory.CreateDirectory(Path.Combine(destination,"stable"));
 foreach(var file in files) { var target=Path.Combine(destination,"objects",file.Sha256);if(!File.Exists(target))File.Copy(ReleaseTrust.SafeFile(folder,file.Path),target);else if(!ReleaseTrust.Matches(target,file))throw new IOException("Kolize obsahu serveru."); }
 var bytes=JsonSerializer.SerializeToUtf8Bytes(signed,ReleaseTrust.Json); File.WriteAllBytes(Path.Combine(folder,".release.json"),bytes);
 var feed=Path.Combine(destination,"stable",platform+".json");File.WriteAllBytes(feed+".tmp",bytes);File.Move(feed+".tmp",feed,true);
 Console.WriteLine($"Podepsaný feed {platform} {version}: {files.Count} souborů. Nic nebylo nahráno na server.");return;
}
throw new ArgumentException("verify FOLDER PLATFORM | keygen PRIVATE.p8 | publish FOLDER PLATFORM VERSION OUTPUT PRIVATE.p8");
