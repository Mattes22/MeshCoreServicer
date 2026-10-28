using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
using System.Text;
using System.Text.RegularExpressions;
if(args.Length!=1)throw new ArgumentException("ArtifactAudit APP_FOLDER");
int checkedAssemblies=0,documents=0;
foreach(var file in Directory.GetFiles(args[0],"MeshCore*.dll",SearchOption.AllDirectories)) {
 using var stream=File.OpenRead(file);using var pe=new PEReader(stream);
 if(!pe.HasMetadata)continue;
 foreach(var entry in pe.ReadDebugDirectory().Where(e=>e.Type==DebugDirectoryEntryType.EmbeddedPortablePdb)) {
  using var provider=pe.ReadEmbeddedPortablePdbDebugDirectoryData(entry);var reader=provider.GetMetadataReader();
  foreach(var document in reader.Documents){var name=reader.GetString(reader.GetDocument(document).Name);if(Regex.IsMatch(name,@"[/\\](Users|home)[/\\]",RegexOptions.IgnoreCase))throw new InvalidDataException("Private development path found in "+Path.GetFileName(file));documents++;}
  foreach(var handle in reader.CustomDebugInformation){var data=reader.GetBlobBytes(reader.GetCustomDebugInformation(handle).Value);var text=Encoding.UTF8.GetString(data);if(Regex.IsMatch(text,@"/(Users|home)/[A-Za-z0-9_.-]+/"))throw new InvalidDataException("Private debug metadata found in "+Path.GetFileName(file));}
 }
 checkedAssemblies++;
}
Console.WriteLine($"Checked {checkedAssemblies} application assemblies and {documents} embedded PDB source paths; no private home paths.");
