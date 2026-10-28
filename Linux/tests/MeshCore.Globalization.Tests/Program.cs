using System.Globalization;
using System.Text;

// Standalone runtime check: no application startup, persistence, BLE or network.
int checks = 0;
void Check(bool result, string label)
{
    if (!result) throw new InvalidOperationException(label);
    checks++;
    Console.WriteLine("PASS " + label);
}

var czech = CultureInfo.GetCultureInfo("cs-CZ");
Check(czech.NumberFormat.NumberDecimalSeparator == ",", "Czech decimal separator");
Check(decimal.Parse("1234,5", czech) == 1234.5m, "Czech decimal parsing");
Check(1234.5m.ToString("F1", czech) == "1234,5", "Czech decimal formatting");
Check(czech.TextInfo.ToLower("ŽLUŤOUČKÝ KŮŇ") == "žluťoučký kůň", "Czech case conversion");
Check(czech.CompareInfo.Compare("h", "ch") < 0 && czech.CompareInfo.Compare("ch", "i") < 0,
      "Czech ch collation");
Check("c\u030c".Normalize(NormalizationForm.FormC) == "č", "Unicode normalization");
Check(new DateTime(2026, 10, 27).ToString("d. MMMM yyyy", czech) == "27. října 2026",
      "Czech month names");
if (OperatingSystem.IsLinux())
{
    var libraries = File.ReadLines("/proc/self/maps")
        .Where(line => line.Contains("/libicu", StringComparison.Ordinal))
        .Select(line => Path.GetFileName(line.Split(' ', StringSplitOptions.RemoveEmptyEntries)[^1]))
        .Distinct().Order().ToArray();
    Check(libraries.Any(name => name.StartsWith("libicuuc.so.", StringComparison.Ordinal)) &&
          libraries.Any(name => name.StartsWith("libicui18n.so.", StringComparison.Ordinal)),
          "System ICU loaded; invariant mode is not used");
    if (args.Length > 0)
    {
        if (args.Length != 2 || args[0] != "--require-icu-major" || !int.TryParse(args[1], out int major))
            throw new ArgumentException("--require-icu-major NUMBER");
        Check(libraries.All(name => name.Contains(".so." + major + ".", StringComparison.Ordinal) ||
                                    name.EndsWith(".so." + major, StringComparison.Ordinal)),
              "Only expected ICU major version loaded: " + major);
    }
    Console.WriteLine("Loaded ICU: " + string.Join(", ", libraries));
}
Console.WriteLine($"Globalization: {checks} checks passed; runtime {Environment.Version}; no BLE/LoRa.");
