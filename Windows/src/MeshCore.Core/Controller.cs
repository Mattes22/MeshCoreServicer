using System.Collections.ObjectModel;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace MeshCore.Core;

public interface ICredentialStore { string? Load(string node); void Save(string node, string password); void Delete(string node); }
public record ConsoleLine(DateTimeOffset Date, string Node, string Command, string Response, string State);
public record LogEvent(DateTimeOffset Date, string Category);
public sealed partial class Controller : Observable
{
    public const string Version = "0.7.3";
    private readonly LocalStore store;
    private readonly ICredentialStore credentials;
    public readonly MeshSession Session;
    public LibraryDocument Library { get; private set; } = new();
    public AccountDocument? Archive { get; private set; }
    public SelfInfo? Self { get; private set; }
    public DeviceInfo? Device { get; private set; }
    public ushort? Battery { get; private set; }
    public ObservableCollection<Contact> Contacts { get; } = [];
    public ObservableCollection<SettingField> Settings { get; } = new(Commands.Keys.Select(k => new SettingField(k)));
    public List<ChannelInfo> Channels { get; } = [];
    public List<ConsoleLine> Console { get; } = [];
    public List<LogEvent> Log { get; } = [];
    public Dictionary<string, DateTimeOffset> Verified { get; } = [];
    public Dictionary<string, string> DiscoveryInfo { get; } = [];
    public List<AccessEntry> Access { get; private set; } = [];
    public List<Neighbour> Neighbours { get; private set; } = [];
    public string TelemetryText { get; private set; } = "Nenačteno";
    public string RegionText { get; private set; } = "Nenačteno";
    public string Firmware { get; private set; } = "";
    public string Board { get; private set; } = "";
    public string Clock { get; private set; } = "";
    public RepeaterStatus? Status { get; private set; }
    public DateTimeOffset? StatusRead { get; private set; }
    public bool Initialized { get; private set; }
    public bool Busy { get; private set; }
    public string Progress { get; private set; } = "Připraveno";
    public string? Error { get; private set; }
    public string? SelectedNode { get; private set; }
    public string? Conversation { get; private set; }
    public bool ReadingConversation { get; set; }
    public bool Monitoring { get; private set; }
    public DateTimeOffset? NextMonitor { get; private set; }
    public Contact? Node => Contacts.FirstOrDefault(c => c.Id == SelectedNode);
    public bool Admin => Initialized && !Session.RequiresReconnect && adminNode != null && adminNode == SelectedNode;
    public string? StorageError => store.Error;
    public CompanionProfile? Profile => Library.Profiles.FirstOrDefault(p => p.Account == Archive?.Account);
    public DeviceOptions Options => Profile?.Options ?? Library.Defaults;
    public NodeOperations Operations => Archive != null && SelectedNode != null && Archive.Nodes.TryGetValue(SelectedNode, out var node) ? node : new();
    public int Unread => Archive?.Messages.Count(m => !m.Outgoing && !m.Seen) ?? 0;
    public IReadOnlyList<string> History => Console.Where(l => l.Node == SelectedNode && !l.Command.StartsWith('[')).Select(l => l.Command).Distinct().Reverse().Take(50).ToArray();
    public Func<string, string, Task<bool>> Confirm { get; set; } = (_, _) => Task.FromResult(false);
    public event Action? Changed;
    public event Action<ChatRecord>? NotifyMessage;
    private string? adminNode;
    private Guid epoch = Guid.NewGuid();
    private readonly HashSet<string> secrets = [];
    private bool syncWanted, liveMessages, accountReady;
    private uint? discoveryTag;
    private DateTimeOffset discoveryUntil;
    private Task saving = Task.CompletedTask;
    public Controller(IMeshTransport transport, ICredentialStore credentials, LocalStore? store = null, RemoteRequestPacer? pacer = null, TimeSpan? remoteTimeout = null)
    {
        this.store = store ?? new(); this.credentials = credentials; Session = new(transport, pacer: pacer, remoteTimeout: remoteTimeout);
        Session.Event += Receive; Session.CliReply += ObserveCli; Session.Malformed += () => AddLog("Odmítnut neplatný rámec");
        transport.Disconnected += Disconnected;
    }
    public async Task Start() { Library = await store.Load("library.json", () => new LibraryDocument(), l => l.Validate()); Update(); }
    public async Task Flush() { await saving; }
    public Task SaveLibrary() => store.Save("library.json", Library, l => l.Validate());
    private void Persist()
    {
        if (Archive == null) return;
        Archive.Messages = Archive.Messages.TakeLast(5000).ToList(); Archive.Validate();
        saving = Task.WhenAll(saving, store.Save("account-" + Archive.Account + ".json", Archive, a => a.Validate()));
    }
    private void Update() { Notify(null); Changed?.Invoke(); }
    private void AddLog(string category) { Log.Add(new(DateTimeOffset.UtcNow, category)); if (Log.Count > 2000) Log.RemoveAt(0); Update(); }
    public string Clean(string text) { foreach (var secret in secrets.Where(x => x.Length > 0)) text = text.Replace(secret, "[skryto]", StringComparison.Ordinal); return text; }
    public async Task Run(string title, Func<Task> action)
    {
        if (Busy) return; Busy = true; Progress = title; Error = null; Update();
        try { await action(); Progress = "Dokončeno"; }
        catch (Exception e) { Error = Clean(e.Message); Progress = "Operace selhala"; Monitoring = false; NextMonitor = null; AddLog("Operace selhala; původní text chyby se neexportuje"); }
        finally { Busy = false; Update(); }
    }
    public async Task Initialize(ulong address, string? expectedIdentity = null)
    {
        await Run("Načítám lokální údaje companionu…", async () =>
        {
            var generation = epoch; await Session.Initialize();
            if (Self == null || expectedIdentity != null && Self.Id != expectedIdentity) throw new MeshException("Identita companionu neodpovídá vybranému profilu. Odpojte jej a vyberte správné zařízení.");
            await Flush();
            var old = Archive?.Account;
            Archive = await store.Load("account-" + Self.Id + ".json", () => new AccountDocument { Account = Self.Id }, a => { a.Validate(); if (a.Account != Self.Id) throw new MeshException("Cizí historie."); });
            if (old != Self.Id) { Console.Clear(); Log.Clear(); secrets.Clear(); SelectedNode = null; Conversation = null; }
            if (generation != epoch) throw new IOException("Spojení se během inicializace změnilo.");
            var profile = Library.Profiles.FirstOrDefault(p => p.Account == Self.Id);
            if (profile == null)
            {
                if (Library.Profiles.Count >= 32) throw new MeshException("Nejvýše 32 profilů; nejprve odstraňte nepoužívaný profil.");
                profile = new() { Account = Self.Id, Options = JsonSerializer.Deserialize<DeviceOptions>(JsonSerializer.Serialize(Library.Defaults))! }; Library.Profiles.Add(profile);
            }
            profile.Name = Self.Name; profile.BluetoothAddress = address; profile.LastConnected = DateTimeOffset.UtcNow; await SaveLibrary();
            foreach (var record in Archive.Messages) { record.Ack = null; record.AckDeadline = null; if (record.Delivery is "Odesílám" or "Čekám na ACK") record.Delivery = "Výsledek neověřený po ukončení předchozí relace"; }
            accountReady = true;
            if (Device != null) await Session.Channels(Device.Channels);
            await Session.SyncMessages();
            if (generation != epoch) throw new IOException("Spojení se během inicializace změnilo.");
            Initialized = true; liveMessages = true; syncWanted = false; Persist(); AddLog("Načteny lokální informace a fronta; žádné LoRa vysílání nebylo spuštěno");
        });
    }
    public void Disconnected()
    {
        epoch = Guid.NewGuid(); accountReady = false; Initialized = false; adminNode = null; Self = null; Device = null; Battery = null; Contacts.Clear(); Channels.Clear();
        SetupSteps.Clear(); SetupSummary = "Prvotní nastavení zatím nebylo načtené."; Firmware = Board = Clock = ""; TelemetryText = RegionText = "Nenačteno"; Status = null; StatusRead = null; Access.Clear(); Neighbours.Clear(); Verified.Clear(); DiscoveryInfo.Clear();
        foreach (var f in Settings) { f.Actual = null; f.Draft = ""; f.State = "Nenačteno"; f.ReadAt = null; }
        foreach (var m in Archive?.Messages ?? []) if (m.Delivery is "Odesílám" or "Čekám na ACK") { m.Delivery = "Výsledek neověřený po odpojení"; m.Ack = null; m.AckDeadline = null; }
        Monitoring = false; NextMonitor = null; liveMessages = false; syncWanted = false; observations.Clear(); earlyAcks.Clear(); contactsWanted.Clear(); discoveryTag = null; Persist(); AddLog("BLE relace ukončena; správce a monitoring zrušeny");
    }
    private void Receive(Frame frame)
    {
        switch (frame.Payload)
        {
            case SelfInfo own: Self = own; break;
            case DeviceInfo info: Device = info; break;
            case Contact c:
                var old = Contacts.FirstOrDefault(x => x.Id == c.Id); if (old != null) Contacts.Remove(old);
                Contacts.Add(old?.Stored == true ? c with { Stored = true } : c); break;
            case ChannelInfo channel: Channels.RemoveAll(x => x.Index == channel.Index); Channels.Add(channel); break;
            case Incoming message when message.Type != 1: ReceiveDirect(message); break;
            case ChannelIncoming message: ReceiveChannel(message); break;
            case Observation observation: Observe(observation); break;
            case Discovery discovery when discoveryTag == discovery.Tag && DateTimeOffset.UtcNow < discoveryUntil:
                var id = Convert.ToHexStringLower(discovery.Key); Verified[id] = DateTimeOffset.UtcNow;
                DiscoveryInfo[id] = $"Odpověď na companionu RSSI {discovery.CompanionRssi} dBm, SNR {discovery.CompanionSnr:F2} dB; požadavek na repeateru SNR {discovery.RepeaterSnr:F2} dB";
                if (discovery.Key.Length == 32 && !Contacts.Any(c => c.Id == id)) Contacts.Add(new(discovery.Key, discovery.Kind, "Objevený uzel " + id[..8], 0, 0, 0, false) { PathLength = 0 });
                AddLog("Přijata odpověď discovery"); break;
        }
        if (frame.Code == 12) Battery = (ushort)frame.Payload!;
        if (frame.Code == 2) { var stored = Contacts.Where(c => c.Stored).ToArray(); foreach (var c in stored) Contacts.Remove(c); }
        if (frame.Code is 0x80 or 0x81) { contactsWanted.Add(Convert.ToHexStringLower(frame.Prefix!)); AddLog("Přijat advert nebo změna cesty"); }
        if (frame.Code == 0x83) syncWanted = true;
        if (frame.Code == 0x82) Acknowledge((uint)frame.Payload!);
        Update();
    }
    private readonly HashSet<string> contactsWanted = [];
    public async Task Tick()
    {
        var now = DateTimeOffset.UtcNow;
        bool dirty = false;
        foreach (var m in Archive?.Messages ?? []) if (m.AckDeadline < now && m.Delivery == "Čekám na ACK") { m.Delivery = "ACK nedorazil v limitu · výsledek neověřený"; m.AckDeadline = null; dirty = true; }
        if (dirty) { Persist(); Update(); }
        if (!Initialized || Busy || Session.RequiresReconnect) return;
        if (contactsWanted.Count > 0)
        {
            var id = contactsWanted.First(); contactsWanted.Remove(id); await Run("Aktualizuji kontakt po advertu…", async () => { await Session.Contact(Codec.Key(id)); }); return;
        }
        if (syncWanted) { syncWanted = false; await Run("Přijímám frontu zpráv…", async () => { await Session.SyncMessages(); }); return; }
        if (Monitoring && NextMonitor <= now)
        { NextMonitor = now.AddMinutes(Options.MonitorMinutes); await Ping(); }
    }
    public async Task<bool> SelectNode(string? id)
    {
        if (Busy) return false;
        if (SelectedNode == id) return true;
        if (Settings.Any(f => f.Dirty) && !await Confirm("Zahodit rozepsané změny?", "Přepnutí repeateru odstraní neuložené návrhy; zařízení se tím nemění.")) return false;
        SelectedNode = id; adminNode = null; Monitoring = false; NextMonitor = null; SetupSteps.Clear(); SetupSummary = "Prvotní nastavení zatím nebylo načtené."; Firmware = Board = Clock = ""; TelemetryText = RegionText = "Nenačteno"; Status = null; Access.Clear(); Neighbours.Clear();
        foreach (var f in Settings) { f.Actual = null; f.Draft = ""; f.State = "Nenačteno"; f.ReadAt = null; } Update(); return true;
    }
    public Task LoadContacts() => Run("Načítám kontakty companionu…", async () => { await Session.Contacts(); });
    public Task StoreContact(Contact c) => Run("Ukládám objevený kontakt…", async () => { await Session.Contacts(); if (!Contacts.Any(x => x.Id == c.Id && x.Stored)) { await Session.AddContact(c); await Session.Contact(c.Key); } });
    public Task Discover() => Run("Odesílám zero-hop discovery…", async () =>
    { if (!Initialized || Device?.Protocol < 8) throw new MeshException("Discovery vyžaduje připojený companion protokol v8+."); discoveryTag = (uint)Random.Shared.NextInt64(1, uint.MaxValue); discoveryUntil = DateTimeOffset.UtcNow.AddSeconds(30); await Session.Discover(discoveryTag.Value); });
    public string? LoadPassword() => Node == null ? null : credentials.Load(Node.Id);
    public void ForgetPassword() { if (Node != null) credentials.Delete(Node.Id); }
    public Task Login(string password, bool remember) => Run("Přihlašuji správce repeateru…", async () =>
    {
        var c = RequireNode(); var generation = epoch; adminNode = null; secrets.Add(password); var permissions = await Session.Login(c.Key, password);
        if ((permissions & 1) == 0) throw new MeshException("Repeater neposkytl oprávnění správce.");
        StillCurrent(c, generation); adminNode = c.Id; Verified[c.Id] = DateTimeOffset.UtcNow; if (remember) credentials.Save(c.Id, password);
        Resolve("Heslo správce · ověřte přihlášením"); AddLog("Repeater potvrdil přihlášení správce");
    });
    private Contact RequireNode(bool admin = false)
    {
        if (!Initialized || Node is not { Stored: true, Kind: 2, Key.Length: 32 } c || admin && !Admin) throw new MeshException("Připojte companion, zvolte uložený repeater a případně přihlaste správce.");
        if (Contacts.Count(x => x.Stored && x.Key.Take(6).SequenceEqual(c.Key.Take(6))) != 1) throw new MeshException("Nejednoznačný šestibajtový prefix kontaktu. CLI nelze bezpečně adresovat.");
        return c;
    }
    private NodeOperations MutableOps()
    {
        if (Archive == null || SelectedNode == null) throw new MeshException("Není vybraný uzel.");
        if (!Archive.Nodes.TryGetValue(SelectedNode, out var op)) { if (Archive.Nodes.Count >= 32) throw new MeshException("Historie už obsahuje 32 uzlů."); Archive.Nodes[SelectedNode] = op = new(); } return op;
    }
    private void BeginChange(string key, string? expected = null)
    { var op = MutableOps(); op.Pending.RemoveAll(c => c.Key == key); op.Pending.Add(new(Guid.NewGuid(), key, Commands.Keys.Contains(key) ? expected : null, DateTimeOffset.UtcNow)); op.Pending = op.Pending.TakeLast(50).ToList(); Persist(); }
    public void Resolve(string key) { MutableOps().Pending.RemoveAll(c => c.Key == key); Persist(); Update(); }
    public Task Ping() => Run("Načítám provozní stav po LoRa…", async () =>
    {
        var c = RequireNode(); var status = await Session.Status(c.Key); RecordStatus(c, status);
    });
    private void RecordStatus(Contact c, RepeaterStatus status)
    {
        Status = status; StatusRead = DateTimeOffset.UtcNow; Verified[c.Id] = StatusRead.Value; var op = MutableOps();
        if (op.Samples.LastOrDefault() is { } previous && status.Uptime < previous.Status.Uptime) { op.RestartRequest = StatusRead; op.ClockAfterRestart = null; op.ReachableAfterRestart = null; }
        op.Samples.Add(new(StatusRead.Value, status)); op.Samples = op.Samples.TakeLast(2000).ToList(); if (op.RestartRequest != null) op.ReachableAfterRestart = StatusRead; Persist();
    }
    public Task ReadConfig(IEnumerable<string>? keys = null) => Run("Načítám konfiguraci repeateru…", async () =>
    {
        var c = RequireNode(true); var wanted = (keys ?? Commands.BasicKeys).ToArray();
        if (Settings.Any(f => wanted.Contains(f.Key) && f.Dirty) && !await Confirm("Nahradit návrhy?", "Čtení nahradí rozepsané hodnoty vybraných polí.")) return;
        foreach (var key in wanted) await ReadField(c, key);
    });
    private async Task<string?> ReadField(Contact c, string key)
    {
        var generation = epoch; var field = Settings.Single(f => f.Key == key); field.State = "Čtu…"; Update();
        try
        {
            var reply = await Session.Cli(c.Key, "get " + key); StillCurrent(c, generation);
            if (Commands.Error(reply)) { field.Actual = null; field.Draft = ""; field.ReadAt = null; field.State = "Nepodporované / odmítnuto"; return null; }
            if (!reply.TrimStart().StartsWith('>')) throw new MeshException("Repeater nevrátil očekávanou hodnotu konfigurace.");
            var value = Commands.Value(reply);
            field.Actual = field.Draft = value; field.ReadAt = DateTimeOffset.UtcNow; field.State = "Načteno"; Verified[c.Id] = DateTimeOffset.UtcNow; return value;
        }
        catch (Exception e)
        {
            if (generation == epoch && SelectedNode == c.Id) { field.ReadAt = null; field.State = "Čtení selhalo · hodnota neověřená"; Update(); }
            throw new MeshException("Čtení get " + key + " selhalo: " + Clean(e.Message));
        }
    }

    public Task SaveConfig(IEnumerable<string>? keys = null) => Run("Ukládám vybrané změny…", async () =>
    {
        var c = RequireNode(true); var generation = epoch; var fields = Settings.Where(f => f.Dirty && (keys == null || keys.Contains(f.Key))).ToArray();
        if (fields.Length == 0) return;
        if (fields.Any(f => f.Key == "af") && fields.Any(f => f.Key == "dutycycle")) throw new MeshException("af a dutycycle mění stejné pole; vyberte jen jednu hodnotu.");
        var changes = fields.Select(f => (f.Key, Value: Commands.Validate(f.Key, f.Draft))).ToArray();
        var summary = string.Join('\n', fields.Select(f => $"{f.Key}: {f.Actual} → {f.Draft}"));
        if (changes.Any(c => c.Key == "radio")) summary += "\nRádio se aktivuje po restartu. Může se přerušit spojení; companion musí používat shodné parametry.";
        if (!await Confirm("Uložit změny repeateru?", summary + "\nKaždý krok se ověří zpětným čtením, při chybě se další zápisy zastaví.")) return;
        StillCurrent(c, generation); foreach (var change in changes) await WriteSetting(c, change.Key, change.Value);
    });
    private async Task WriteSetting(Contact c, string key, string value)
    {
        var generation = epoch; StillCurrent(c, generation); BeginChange(key, value); var field = Settings.Single(f => f.Key == key); field.State = "Odesílám…"; Update();
        var reply = await Session.Cli(c.Key, "set " + key + " " + value);
        if (!reply.StartsWith("OK", StringComparison.OrdinalIgnoreCase)) { field.State = "Zápis nepotvrzen"; throw new MeshException("Repeater zápis nepotvrdil: " + Clean(reply)); }
        if (key == "radio") BeginChange("Rádio · vyžaduje restart");
        field.State = "Ověřuji…"; var actual = await Session.Cli(c.Key, "get " + key);
        if (Commands.Error(actual)) { field.State = "Zápis přijat; ověření selhalo"; throw new MeshException("Změna přijata, zpětné čtení selhalo."); }
        StillCurrent(c, generation); field.Actual = Commands.Value(actual); field.ReadAt = DateTimeOffset.UtcNow;
        if (!Commands.Same(key, field.Actual, value)) { field.State = "Vrácena jiná hodnota"; throw new MeshException("Zpětně načtená hodnota se liší; návrh zůstal zachovaný, další zápisy se zastavily."); }
        field.Draft = field.Actual; field.State = "Potvrzeno a ověřeno"; Resolve(key);
        var alternate = key == "af" ? "dutycycle" : key == "dutycycle" ? "af" : null;
        if (alternate != null) { var f = Settings.Single(x => x.Key == alternate); f.Actual = null; f.Draft = ""; f.State = "Znovu načtěte"; }
    }
    public Task SendCli(string command) => Run("Odesílám vzdálený CLI příkaz…", async () =>
    {
        var c = RequireNode(true); var generation = epoch; command = command.Trim(); Commands.ValidateCommand(command);
        if ((Commands.NoReply(command) || Commands.RadioWarning(command)) && !await Confirm("Potvrdit rizikový příkaz?", Clean(command) + "\nMůže přerušit spojení. Přijetí companionem nepotvrzuje restart ani provedení změny.")) return;
        StillCurrent(c, generation); var sensitive = Commands.Sensitive(command); var safe = sensitive ? "[citlivý příkaz skryt]" : Clean(command);
        Console.Add(new(DateTimeOffset.UtcNow, c.Id, safe, "Čekám na odpověď…", "Odesílám")); var line = Console.Count - 1; Update();
        if (!Commands.ReadOnly(command))
        {
            if (Commands.Entry(command) is { } e && e.Command.StartsWith("set ", StringComparison.Ordinal)) BeginChange(e.Command[4..], Commands.Validate(e.Command[4..], command[e.Command.Length..].Trim()));
            else BeginChange(Commands.NoReply(command) ? "Restart" : "CLI · ověřte stav ručně");
        }
        try
        {
            var reply = await Session.Cli(c.Key, command, Commands.NoReply(command));
            Console[line] = Console[line] with { Response = sensitive ? "[odpověď citlivého příkazu skryta]" : Clean(reply), State = Commands.NoReply(command) ? "Přijato companionem · provedení neověřeno" : Commands.Error(reply) ? "Repeater vrátil chybu" : "Odpověď přijata" };
            if (Commands.NoReply(command)) { var op = MutableOps(); op.RestartRequest = DateTimeOffset.UtcNow; op.ClockAfterRestart = null; op.ReachableAfterRestart = null; Persist(); }
            if (command.StartsWith("set radio ", StringComparison.Ordinal) && reply.StartsWith("OK", StringComparison.Ordinal)) BeginChange("Rádio · vyžaduje restart");
        }
        catch { Console[line] = Console[line] with { State = "Výsledek neověřený", Response = "Operace selhala; zkontrolujte stav před opakováním." }; throw; }
        finally { if (Console.Count > 500) Console.RemoveRange(0, Console.Count - 500); }
    });
    private void ObserveCli(byte[] key, string command, string reply)
    {
        if (Node?.Key.SequenceEqual(key) != true) return;
        if (command == "ver" && !Commands.Error(reply)) Firmware = Clean(reply.Length <= 200 ? reply : reply[..200]);
        if (command == "board" && !Commands.Error(reply)) Board = Clean(reply);
        if (command == "clock" && !Commands.Error(reply)) Clock = reply;
        if (Archive != null && Commands.Entry(command) is { } entry)
        {
            var firmware = Firmware; Library.Evidence.RemoveAll(e => e.Account == Archive.Account && e.Repeater == Node.Id && e.Firmware == firmware && e.Command == entry.Command && (firmware.Length > 0 || e.Session == epoch));
            Library.Evidence.Add(new(Archive.Account, Node.Id, firmware, epoch, entry.Command, CommandEvidence.Classify(reply), DateTimeOffset.UtcNow)); Library.Evidence = Library.Evidence.TakeLast(1024).ToList();
            saving = Task.WhenAll(saving, SaveLibrary());
        }
        Update();
    }
    public string Support(string command)
    {
        var entry = Commands.Entry(command); var e = Library.Evidence.LastOrDefault(e => e.Account == Archive?.Account && e.Repeater == SelectedNode && e.Command == entry?.Command && e.Firmware == Firmware && (Firmware.Length > 0 || e.Session == epoch));
        return e == null ? "Pouze katalog · na tomto uzlu neověřeno" : $"{e.Result} · {e.Date.LocalDateTime:g} (nepotvrzuje výslednou konfiguraci)";
    }
}
