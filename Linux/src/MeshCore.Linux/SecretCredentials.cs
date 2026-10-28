using System.Diagnostics;
using MeshCore.Core;
namespace MeshCore.Linux;
public sealed class SecretCredentials : ICredentialStore
{
    private static string? Run(string operation, string node, string? password = null)
    {
        Codec.Key(node);
        ProcessStartInfo info = new("secret-tool") { UseShellExecute = false, RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
        info.ArgumentList.Add(operation); if (operation == "store") { info.ArgumentList.Add("--label=MeshCore Servicer"); }
        foreach (var value in new[] { "application","org.meshcoreservicer.app","node",node }) info.ArgumentList.Add(value);
        using var process = Process.Start(info) ?? throw new MeshException("Nelze otevřít systémovou klíčenku Secret Service.");
        var output = process.StandardOutput.ReadToEndAsync(); var error = process.StandardError.ReadToEndAsync();
        if (password != null) process.StandardInput.Write(password); process.StandardInput.Close();
        if (!process.WaitForExit(10000)) { process.Kill(); throw new MeshException("Systémová klíčenka neodpovídá. Odemkněte ji a zkuste akci ručně znovu."); }
        _ = error.GetAwaiter().GetResult();
        if (process.ExitCode != 0) { if (operation == "lookup") return null; throw new MeshException("Heslo se nepodařilo uložit do systémové klíčenky. Heslo se neukládá do souboru."); }
        return output.GetAwaiter().GetResult().TrimEnd('\r','\n');
    }
    public string? Load(string node) => Run("lookup",node);
    public void Save(string node, string password) => Run("store",node,password);
    public void Delete(string node) => Run("clear",node);
}
