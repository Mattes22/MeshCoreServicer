using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace MeshCore.Core;

public abstract class Observable : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    protected void Notify([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
    protected bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    { if (EqualityComparer<T>.Default.Equals(field, value)) return false; field = value; Notify(name); return true; }
}
public sealed class SettingField(string key) : Observable
{
    public string Key { get; } = key;
    public string Title => Commands.Entry("get " + Key)?.Title ?? Key;
    private string? actual;
    private string draft = "", state = "Nenačteno";
    public string? Actual { get => actual; set { Set(ref actual, value); Notify(nameof(Dirty)); } }
    public string Draft { get => draft; set { Set(ref draft, value); Notify(nameof(Dirty)); } }
    public string State { get => state; set => Set(ref state, value); }
    public DateTimeOffset? ReadAt { get; set; }
    public bool Dirty => Actual != null && !Commands.Same(Key, Actual, Draft);
}
public sealed class DeviceOptions
{
    public bool AutoReconnect { get; set; } = true;
    public bool Suggestions { get; set; } = true;
    public bool Help { get; set; } = true;
    public bool History { get; set; } = true;
    public bool SuggestWrites { get; set; }
    public bool EnterSends { get; set; } = true;
    public int MonitorMinutes { get; set; } = 15;
}
public sealed class CompanionProfile
{
    public string Account { get; set; } = "";
    public string Name { get; set; } = "";
    public string Alias { get; set; } = "";
    public ulong BluetoothAddress { get; set; }
    public DateTimeOffset LastConnected { get; set; }
    public DeviceOptions Options { get; set; } = new();
    [JsonIgnore] public string Display => (Alias.Length > 0 ? Alias : Name) + " · " + Account[..Math.Min(12, Account.Length)] + "…";
    public override string ToString() => Display;
}
public record Shortcut(Guid Id, string Account, string Title, string Command)
{
    public void Validate()
    { Codec.Key(Account); if (Title.Length is < 1 or > 80 || Title.Any(c => c is '\0' or '\r' or '\n') || !Commands.Catalog.Any(c => c.Command == Command) || Commands.Sensitive(Command)) throw new MeshException("Neplatná zkratka: pouze pojmenovaný typ příkazu z katalogu, bez argumentu nebo hesla."); }
    public string Fill(string argument)
    { Validate(); var entry = Commands.Entry(Command)!; var text = Command + (entry.Arguments.Length == 0 ? "" : " " + argument.Trim()); Commands.ValidateCommand(text); return text; }
    public override string ToString() => Title + " · " + (Commands.Entry(Command)?.Syntax ?? Command);
}
public record CommandEvidence(string Account, string Repeater, string Firmware, Guid Session, string Command, string Result, DateTimeOffset Date)
{
    public static string Classify(string reply)
    {
        var text = reply.Trim().ToLowerInvariant(); if (text.StartsWith('>')) return "Odpověď přijata";
        if (text.StartsWith("unknown command") || text.StartsWith("unknown config") || text.StartsWith("not supported") || text.StartsWith("err") && (text.Contains("unsupported") || text.Contains("not supported"))) return "Výslovně nepodporováno";
        return Commands.Error(reply) ? "Příkaz vrátil chybu" : "Odpověď přijata";
    }
}
public record HardwareCheck(string Account, string Node, string CompanionFirmware, string RepeaterFirmware, string App, string Os, string Architecture, string Test, string Result, DateTimeOffset Date);
public sealed class LibraryDocument
{
    public int Version { get; set; } = 1;
    public List<CompanionProfile> Profiles { get; set; } = [];
    public List<Shortcut> Shortcuts { get; set; } = [];
    public List<CommandEvidence> Evidence { get; set; } = [];
    public List<HardwareCheck> Checks { get; set; } = [];
    public bool Notifications { get; set; }
    public bool Sound { get; set; } = true;
    public bool NotificationText { get; set; }
    public HashSet<string> Muted { get; set; } = [];
    public string Theme { get; set; } = "Systém";
    public int InterfaceScale { get; set; } = 100;
    public DeviceOptions Defaults { get; set; } = new();
    public void Validate()
    {
        if (InterfaceScale is not (100 or 115 or 130 or 150)) throw new MeshException("Neplatná velikost rozhraní.");
        if (Defaults.MonitorMinutes is < 5 or > 1440 || Version != 1 || Profiles.Count > 32 || Shortcuts.Count > 128 || Evidence.Count > 1024 || Checks.Count > 256 || Profiles.Select(p => p.Account).Distinct().Count() != Profiles.Count) throw new MeshException("Neplatná knihovna nebo překročený limit.");
        foreach (var p in Profiles) { Codec.Key(p.Account); if (p.Name.Length > 80 || p.Alias.Length > 80 || p.Options.MonitorMinutes is < 5 or > 1440) throw new MeshException("Neplatný profil."); }
        foreach (var s in Shortcuts) { s.Validate(); if (!Profiles.Any(p => p.Account == s.Account)) throw new MeshException("Neznámý účet zkratky."); }
        foreach (var e in Evidence) { Codec.Key(e.Account); Codec.Key(e.Repeater); if (e.Firmware.Length > 200 || !Commands.Catalog.Any(c => c.Command == e.Command)) throw new MeshException("Neplatná evidence."); }
    }
}
public record Capture(DateTimeOffset Date, int? Hops, sbyte Rssi, double Snr)
{ [JsonIgnore] public string Display => $"{Date.LocalDateTime:T} · hopy {Hops?.ToString() ?? "?"} · RSSI {Rssi} dBm · SNR {Snr:F2} dB · příjem na companionu"; }
public sealed class ChatRecord
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Conversation { get; set; } = "";
    public string Title { get; set; } = "";
    public string Sender { get; set; } = "";
    public string Text { get; set; } = "";
    public uint Timestamp { get; set; }
    public DateTimeOffset Date { get; set; } = DateTimeOffset.UtcNow;
    public bool Outgoing { get; set; }
    public bool Seen { get; set; }
    public string Delivery { get; set; } = "Přijato";
    public string? Deduplication { get; set; }
    public string? PacketFingerprint { get; set; }
    public int? Forwardings { get; set; }
    public int? Hops { get; set; }
    public double? Snr { get; set; }
    public List<Capture> Captures { get; set; } = [];
    [JsonIgnore] public uint? Ack { get; set; }
    [JsonIgnore] public DateTimeOffset? AckDeadline { get; set; }
    [JsonIgnore] public string Display => $"{Date.LocalDateTime:g} · {Sender} · {Delivery}\n{Text}" + (Forwardings.HasValue ? $"\nZachyceno {Forwardings} přeposlání (rádiové kopie, nikoliv unikátní uzly / ACK)" : "") + (Hops.HasValue ? $"\nCesta přijatého paketu: {Hops} přeposlání" : "") + (Snr.HasValue ? $" · SNR posledního příjmu na companionu {Snr:F2} dB" : "");
}
public record PendingChange(Guid Id, string Key, string? Expected, DateTimeOffset Date);
public sealed class ConfigSnapshot
{
    public int Version { get; set; } = 1;
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Account { get; set; } = "";
    public string Node { get; set; } = "";
    public string Name { get; set; } = "";
    public DateTimeOffset Date { get; set; } = DateTimeOffset.UtcNow;
    public Dictionary<string, string> Values { get; set; } = [];
    public Dictionary<string, DateTimeOffset> ReadAt { get; set; } = [];
    public void Validate()
    {
        Codec.Key(Account); Codec.Key(Node);
        if (Version != 1 || Name.Length > 128 || Values.Count == 0 || Values.Count > Commands.Keys.Length || Values.ContainsKey("af") && Values.ContainsKey("dutycycle") || ReadAt.Keys.Any(k => !Values.ContainsKey(k)) || ReadAt.Values.Any(d => d > Date.AddSeconds(1))) throw new MeshException("Neplatný snímek.");
        foreach (var (key,value) in Values) Commands.Validate(key, value);
    }
    public override string ToString() => $"{Name} · {Date.LocalDateTime:g}";
}
public record HealthSample(DateTimeOffset Date, RepeaterStatus Status);
public sealed class NodeOperations
{
    public List<HealthSample> Samples { get; set; } = [];
    public List<ConfigSnapshot> Snapshots { get; set; } = [];
    public List<PendingChange> Pending { get; set; } = [];
    public DateTimeOffset? RestartRequest { get; set; }
    public DateTimeOffset? ReachableAfterRestart { get; set; }
    public DateTimeOffset? ClockAfterRestart { get; set; }
}
public sealed class AccountDocument
{
    public int Version { get; set; } = 1;
    public string Account { get; set; } = "";
    public List<ChatRecord> Messages { get; set; } = [];
    public Dictionary<string, NodeOperations> Nodes { get; set; } = [];
    public void Validate()
    {
        Codec.Key(Account); if (Version != 1 || Messages.Count > 5000 || Nodes.Count > 32) throw new MeshException("Neplatná historie.");
        foreach (var m in Messages) if (m.Text.Length > 1024 || m.Captures.Count > 64 || m.Forwardings < 0) throw new MeshException("Neplatný záznam zprávy.");
        foreach (var (key,node) in Nodes)
        {
            Codec.Key(key); if (node.Samples.Count > 2000 || node.Snapshots.Count > 30 || node.Pending.Count > 50) throw new MeshException("Překročený limit historie uzlu.");
            foreach (var s in node.Snapshots) { s.Validate(); if (s.Account != Account || s.Node != key) throw new MeshException("Cizí snímek v historii."); }
            foreach (var change in node.Pending) if (change.Expected != null) Commands.Validate(change.Key, change.Expected);
        }
    }
}
public sealed class LocalStore(string? folder = null)
{
    public static readonly JsonSerializerOptions Json = new() { WriteIndented = true, PropertyNameCaseInsensitive = false };
    private readonly Dictionary<string, byte[]> memory = [];
    private readonly HashSet<string> blocked = [];
    private readonly SemaphoreSlim writer = new(1, 1);
    public string? Error { get; private set; }
    public async Task<T> Load<T>(string name, Func<T> create, Action<T> validate)
    {
        try
        {
            byte[]? data = null;
            if (folder == null) memory.TryGetValue(name, out data);
            else { var path = Path.Combine(folder, name); if (File.Exists(path)) { if (new FileInfo(path).Length > 128_000_000) throw new MeshException("Příliš velká historie."); data = await File.ReadAllBytesAsync(path); } }
            if (data == null) return create();
            var result = JsonSerializer.Deserialize<T>(data, Json) ?? throw new MeshException("Prázdná historie."); validate(result); return result;
        }
        catch { blocked.Add(name); Error = "Lokální soubor je poškozený nebo nedostupný. Původní data se automaticky nepřepíšou."; return create(); }
    }
    public async Task Save<T>(string name, T value, Action<T> validate)
    {
        if (blocked.Contains(name)) return;
        validate(value); var bytes = JsonSerializer.SerializeToUtf8Bytes(value, Json);
        if (bytes.Length > 128_000_000) { Error = "Historie překročila bezpečný limit 128 MB; původní soubor nebyl přepsán."; return; }
        await writer.WaitAsync();
        try
        {
            if (folder == null) { memory[name] = bytes; return; }
            Directory.CreateDirectory(folder); var path = Path.Combine(folder, name); var temp = path + "." + Guid.NewGuid() + ".tmp";
            try { await File.WriteAllBytesAsync(temp, bytes); File.Move(temp, path, true); }
            finally { if (File.Exists(temp)) File.Delete(temp); }
        }
        catch { Error = "Lokální historii se nepodařilo uložit. Změny mohou být jen v paměti."; }
        finally { writer.Release(); }
    }
}
