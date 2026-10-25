using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace MeshCore.Core;

public record CatalogEntry(string Command, string Arguments, string Title, string Detail, bool Changes)
{ public string Syntax => Command + (Arguments.Length == 0 ? "" : " " + Arguments); public override string ToString() => Syntax; }
public static class Commands
{
    public static readonly string[] BasicKeys = ["name", "lat", "lon", "tx", "radio", "advert.interval", "flood.advert.interval", "repeat", "owner.info"];
    public static readonly string[] Keys = [.. BasicKeys, "dutycycle", "af", "path.hash.mode", "flood.max", "flood.max.advert", "flood.max.unscoped", "loop.detect"];
    public static IReadOnlyList<CatalogEntry> Catalog { get; } = JsonSerializer.Deserialize<List<CatalogEntry>>(typeof(Commands).Assembly.GetManifestResourceStream("MeshCore.Core.Catalog.json")!)!;
    public static CatalogEntry? Entry(string input) => Catalog.OrderByDescending(x => x.Command.Length).FirstOrDefault(x => input.Trim() == x.Command || x.Arguments.Length > 0 && input.TrimStart().StartsWith(x.Command + " ", StringComparison.Ordinal));
    public static bool Sensitive(string text) => new[] { "password", "prv", "private", "secret", "pin", "key" }.Any(x => text.Contains(x, StringComparison.OrdinalIgnoreCase));
    public static bool Error(string text) { var s = text.Trim().ToLowerInvariant(); return !s.StartsWith('>') && (s.StartsWith("err") || s.StartsWith("(err") || (s.StartsWith("unknown command") || s.StartsWith("unknown config")) || s.Contains("not supported")); }
    public static bool NoReply(string text) => new[] { "reboot", "clkreboot", "poweroff", "shutdown" }.Any(x => text.StartsWith(x, StringComparison.OrdinalIgnoreCase));
    public static bool RadioWarning(string text) => new[] { "set radio ", "set freq ", "tempradio " }.Any(x => text.StartsWith(x, StringComparison.OrdinalIgnoreCase));
    public static bool ReadOnly(string text) => text.StartsWith("get ", StringComparison.Ordinal) || new[] { "ver", "board", "clock", "neighbors", "region", "region home", "region default", "sensor list" }.Contains(text) || text.StartsWith("region get ", StringComparison.Ordinal) || text.StartsWith("region list ", StringComparison.Ordinal) || text.StartsWith("sensor get ", StringComparison.Ordinal);
    public static string Value(string text) => Regex.Replace(text.Trim(), @"^>\s*", "");
    public static string Validate(string key, string input)
    {
        var v = input.Trim(); if (key == "dutycycle") v = v.TrimEnd('%');
        Codec.ValidateText(v); if (v.Any(c => c is '\r' or '\n')) throw new MeshException("Hodnota musí být jednořádková.");
        bool Number(double lo, double hi) => double.TryParse(v, NumberStyles.Float, CultureInfo.InvariantCulture, out var n) && double.IsFinite(n) && n >= lo && n <= hi;
        bool Integer(int lo, int hi) => int.TryParse(v, NumberStyles.Integer, CultureInfo.InvariantCulture, out var n) && n >= lo && n <= hi;
        var valid = key switch
        {
            "name" => Encoding.UTF8.GetByteCount(v) <= 23 && !v.Contains('|'), "owner.info" => Encoding.UTF8.GetByteCount(v) <= 118,
            "lat" => Number(-90, 90), "lon" => Number(-180, 180), "tx" => Integer(1, 22), "repeat" => v is "on" or "off",
            "dutycycle" => Number(1, 100), "af" => Number(0, 9), "path.hash.mode" => v is "0" or "1" or "2",
            "flood.max" or "flood.max.advert" or "flood.max.unscoped" => Integer(0, 64), "loop.detect" => v is "off" or "minimal" or "moderate" or "strict",
            "advert.interval" => v == "0" || Integer(60, 240) && int.Parse(v, CultureInfo.InvariantCulture) % 2 == 0,
            "flood.advert.interval" => v == "0" || Integer(3, 168), "radio" => Radio(v), _ => false
        };
        if (!valid) throw new MeshException($"Neplatná hodnota pro {key}; použijte uvedený rozsah a desetinnou tečku."); return v;
    }
    private static bool Radio(string value)
    {
        var p = value.Split(',');
        return p.Length == 4 && double.TryParse(p[0], NumberStyles.Float, CultureInfo.InvariantCulture, out var f) && double.IsFinite(f) && f is >= 150 and <= 2500
            && double.TryParse(p[1], NumberStyles.Float, CultureInfo.InvariantCulture, out var b) && new[] { 7.8, 10.4, 15.6, 20.8, 31.25, 41.7, 62.5, 125, 250, 500 }.Contains(b)
            && int.TryParse(p[2], out var sf) && sf is >= 5 and <= 12 && int.TryParse(p[3], out var cr) && cr is >= 5 and <= 8;
    }
    public static void ValidateCommand(string text)
    {
        Codec.ValidateText(text); if (text.Any(c => c is '\r' or '\n')) throw new MeshException("Příkaz musí být jednořádkový.");
        if (Entry(text) is { Arguments.Length: > 0 } e)
        {
            var argument = text[e.Command.Length..].Trim();
            if (argument.Length == 0 || argument.Contains('<') || argument.Contains('>')) throw new MeshException("Doplňte argumenty: " + e.Syntax);
            if (e.Command.StartsWith("set ", StringComparison.Ordinal)) Validate(e.Command[4..], argument);
            if (e.Command == "time" && !uint.TryParse(argument, out _)) throw new MeshException("Čas musí být Unix timestamp UInt32.");
        }
    }
    public static bool Same(string key, string a, string b)
    {
        if (key == "dutycycle") { a = a.TrimEnd('%'); b = b.TrimEnd('%'); }
        if (key == "radio") { var x = a.Split(','); var y = b.Split(','); return x.Length == 4 && y.Length == 4 && x.Zip(y).All(p => NumericSame(p.First, p.Second)); }
        return key is "name" or "owner.info" or "repeat" or "loop.detect" ? a == b : NumericSame(a, b);
    }
    private static bool NumericSame(string a, string b) => double.TryParse(a, NumberStyles.Float, CultureInfo.InvariantCulture, out var x) && double.TryParse(b, NumberStyles.Float, CultureInfo.InvariantCulture, out var y) && double.IsFinite(x) && double.IsFinite(y) && Math.Abs(x - y) < 1e-6;
    public static IEnumerable<string> Suggest(string query, IEnumerable<string> history, bool writes = false, bool useHistory = true)
    {
        if (Sensitive(query)) return [];
        static string Fold(string s) => string.Concat(s.Normalize(NormalizationForm.FormD).Where(c => CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark)).ToLowerInvariant();
        var q = Fold(query.Trim()); var result = new List<string>();
        if (useHistory && q.Length > 0) result.AddRange(history.Where(x => !Sensitive(x) && x != query && (writes || Entry(x)?.Changes == false) && Fold(x).StartsWith(q, StringComparison.Ordinal)));
        if (writes)
        {
            foreach (var (key, values) in new[] { ("repeat", new[] { "on", "off" }), ("path.hash.mode", new[] { "0", "1", "2" }), ("loop.detect", new[] { "off", "minimal", "moderate", "strict" }) })
                if (query.Trim() == "set " + key || query.StartsWith("set " + key + " ", StringComparison.Ordinal))
                    result.AddRange(values.Select(x => "set " + key + " " + x).Where(x => x.StartsWith(query.Trim(), StringComparison.Ordinal) && x != query.Trim()));
        }
        result.AddRange(Catalog.Where(e => (writes || !e.Changes) && e.Command != query.Trim() && (q.Length == 0 || Fold(e.Command).Contains(q) || Fold(e.Title).Contains(q)))
            .OrderByDescending(e => Fold(e.Command).StartsWith(q, StringComparison.Ordinal)).Select(e => e.Command + (e.Arguments.Length == 0 ? "" : " ")));
        return result.Distinct().Take(6);
    }
    public static string Password(string text)
    { if (Encoding.UTF8.GetByteCount(text) is < 1 or > 15 || text.Any(char.IsWhiteSpace) || text.Contains('\0')) throw new MeshException("Heslo musí mít 1–15 UTF-8 bajtů bez mezer a NUL."); return text; }
    public static string Region(string text) => Regex.IsMatch(text, @"^[A-Za-z0-9#._-]{1,30}$") || text == "*" ? text : throw new MeshException("Neplatný název regionu (1–30 ASCII znaků, bez mezer).");
    public static DateTimeOffset? Clock(string text) => DateTimeOffset.TryParseExact(text.Trim(), ["HH:mm - d/M/yyyy 'UTC'", "HH:mm - dd/MM/yyyy 'UTC'"], CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date) ? date.ToUniversalTime() : null;
}
public record AccessEntry(string Prefix, byte Permissions)
{
    public string Role => (Permissions & 3) switch { 1 => "Pouze čtení", 2 => "Čtení a zápis", 3 => "Správce", _ => "Host / odebráno" };
    public static List<AccessEntry> Decode(byte[] bytes)
    {
        var r = new Reader(bytes); List<AccessEntry> result = [];
        while (r.Remaining > 0)
        {
            var rest = bytes[(bytes.Length - r.Remaining)..];
            if (rest.All(x => x == 0)) { if (rest.Length > 15) throw new MeshException("Neplatný padding ACL."); break; }
            result.Add(new(Convert.ToHexStringLower(r.Bytes(6)), r.U8()));
        }
        return result;
    }
}
public record Neighbour(string Key, uint SecondsAgo, double Snr);
public record NeighbourPage(int Total, List<Neighbour> Entries)
{
    public static byte[] Request(ushort offset, uint nonce) => [6, 0, 3, (byte)offset, (byte)(offset >> 8), 0, 32, .. Codec.U32(nonce)];
    public static NeighbourPage Decode(byte[] bytes)
    {
        var r = new Reader(bytes); var total = r.U16(); var count = r.U16();
        if (count > 3 || count > total || r.Remaining < count * 37) throw new MeshException("Neplatná stránka sousedů.");
        List<Neighbour> entries = []; for (int i = 0; i < count; i++) entries.Add(new(Convert.ToHexStringLower(r.Bytes(32)), r.U32(), r.I8() / 4d));
        if (r.Remaining > 15 || r.Bytes(r.Remaining).Any(x => x != 0)) throw new MeshException("Neplatný padding sousedů.");
        return new(total, entries);
    }
}
public static class Telemetry
{
    private static readonly Dictionary<byte, (int Size, double Scale, bool Signed, string Label)> specs = new()
    { [0]=(1,1,false,"Digitální vstup"),[1]=(1,1,false,"Digitální výstup"),[2]=(2,100,true,"Analogový vstup"),[3]=(2,100,true,"Analogový výstup"),[100]=(4,1,false,"Senzor"),[101]=(2,1,false,"Osvětlení · lx"),[102]=(1,1,false,"Přítomnost"),[103]=(2,10,true,"Teplota · °C"),[104]=(1,2,false,"Vlhkost · %"),[115]=(2,10,false,"Tlak · hPa"),[116]=(2,100,false,"Napětí · V"),[117]=(2,1000,false,"Proud · A"),[118]=(4,1,false,"Frekvence · Hz"),[120]=(1,1,false,"Podíl · %"),[121]=(2,1,true,"Výška · m"),[125]=(2,1,false,"Koncentrace · ppm"),[128]=(2,1,false,"Výkon · W"),[130]=(4,1000,false,"Vzdálenost · m"),[131]=(4,1000,false,"Energie · kWh"),[132]=(2,1,false,"Směr · °"),[133]=(4,1,false,"Unix čas · s"),[142]=(1,1,false,"Spínač") };
    private static double Number(byte[] bytes, bool signed, double scale)
    { long n = bytes.Aggregate(0L, (x,b) => (x << 8) | b); if (signed && (bytes[0] & 128) != 0) n -= 1L << (bytes.Length * 8); return n / scale; }
    public static string Decode(byte[] bytes)
    {
        var r = new Reader(bytes); List<string> lines = [];
        while (r.Remaining > 0)
        {
            if (bytes[(bytes.Length - r.Remaining)..].All(x => x == 0)) break;
            var channel = r.U8(); var type = r.U8();
            if (specs.TryGetValue(type, out var s)) lines.Add($"Kanál {channel} · {s.Label}: {Number(r.Bytes(s.Size), s.Signed, s.Scale):G}");
            else if (type is 113 or 134 or 135 or 136)
            {
                int size = type == 136 ? 3 : type == 135 ? 1 : 2; double scale = type == 113 ? 1000 : type == 134 ? 100 : type == 136 ? 10000 : 1;
                var values = Enumerable.Range(0,3).Select(i => Number(r.Bytes(size), type != 135, type == 136 && i == 2 ? 100 : scale)).ToArray();
                lines.Add($"Kanál {channel} · {(type == 136 ? "Poloha °, °, m" : type == 113 ? "Zrychlení · g" : type == 134 ? "Gyroskop · °/s" : "Barva RGB")}: {string.Join(", ", values.Select(x => x.ToString("G", CultureInfo.InvariantCulture)))}");
            }
            else { lines.Add($"Neznámý typ LPP {type}; další pole se neodhadují."); break; }
        }
        return lines.Count == 0 ? "Žádné senzory v odpovědi." : string.Join('\n', lines);
    }
}
