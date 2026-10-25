using System.Runtime.InteropServices;
using System.Text.Json;

namespace MeshCore.Core;

public record SetupReadStep(string Command, string State);

public sealed partial class Controller
{
    public System.Collections.ObjectModel.ObservableCollection<SetupReadStep> SetupSteps { get; } = [];
    public string SetupSummary { get; private set; } = "Prvotní nastavení zatím nebylo načtené.";
    private void StillCurrent(Contact c, Guid generation)
    { if (generation != epoch || SelectedNode != c.Id || !Initialized) throw new IOException("Spojení nebo vybraný repeater se změnil. Další kroky se neprovedou."); }
    public Task ReadInfo() => Run("Načítám verzi a hodiny…", async () =>
    { var c = RequireNode(true); foreach (var command in new[] { "ver", "board", "clock" }) { var reply = await Session.Cli(c.Key, command); if (Commands.Error(reply)) throw new MeshException(Clean(reply)); } Verified[c.Id] = DateTimeOffset.UtcNow; });
    public Task SyncClock() => Run("Synchronizuji hodiny…", async () =>
    {
        var c = RequireNode(true); var generation = epoch;
        if (!await Confirm("Synchronizovat hodiny repeateru?", "Použije se aktuální čas tohoto PC. Zkontrolujte systémové datum. Firmware neposouvá čas zpět; po restartu synchronizaci opakujte ručně.")) return;
        StillCurrent(c, generation); BeginChange("Hodiny"); var time = (uint)DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var reply = await Session.Cli(c.Key, "time " + time, commandAtSend: () => { time = (uint)DateTimeOffset.UtcNow.ToUnixTimeSeconds(); return "time " + time; }); if (!reply.StartsWith("OK", StringComparison.OrdinalIgnoreCase)) throw new MeshException("Nastavení času nepotvrzeno.");
        var check = await Session.Cli(c.Key, "clock"); var date = Commands.Clock(check);
        if (date == null || date < DateTimeOffset.FromUnixTimeSeconds(time).AddSeconds(-60) || date > DateTimeOffset.UtcNow.AddSeconds(60)) throw new MeshException("Načtený čas neodpovídá času PC; změna není plně ověřená.");
        MutableOps().ClockAfterRestart = DateTimeOffset.UtcNow; Resolve("Hodiny");
    });
    public Task ReadTelemetry() => Run("Načítám telemetrii…", async () => { var c = RequireNode(true); TelemetryText = Telemetry.Decode(await Session.Binary(c.Key, [3, 0, 0, 0])); });
    private async Task FetchAccess(Contact c) { Access = AccessEntry.Decode(await Session.Binary(c.Key, [5, 0, 0])); Verified[c.Id] = DateTimeOffset.UtcNow; }
    public Task ReadAccess() => Run("Načítám ACL…", async () => await FetchAccess(RequireNode(true)));
    public Task ChangeAccess(string key, byte role) => Run("Měním oprávnění…", async () =>
    {
        var c = RequireNode(true); var generation = epoch; key = Convert.ToHexStringLower(Codec.Key(key));
        if (role > 3 || key == Self?.Id && role != 3) throw new MeshException("Neplatná role nebo pokus odebrat vlastní správu.");
        await FetchAccess(c); var matches = Access.Where(a => a.Prefix == key[..12]).ToArray();
        if (matches.Length > 1) throw new MeshException("Nejednoznačný prefix ACL.");
        byte effective = role == 0 ? (byte)0 : (byte)((matches.FirstOrDefault()?.Permissions ?? 0) & 0xfc | role);
        if (!await Confirm("Změnit přístup?", $"{c.Name}\n{key}\nRole {role}; byte oprávnění {effective}. 0 odebere přístup, 3 poskytne správu. ACL vrací pouze prefixy a může být oříznutá.")) return;
        StillCurrent(c, generation); BeginChange("ACL"); var reply = await Session.Cli(c.Key, $"setperm {key} {effective}");
        if (!reply.StartsWith("OK", StringComparison.OrdinalIgnoreCase)) throw new MeshException("Změna ACL nepotvrzena.");
        await FetchAccess(c); matches = Access.Where(a => a.Prefix == key[..12]).ToArray();
        if (role != 0 && matches.Length == 1 && matches[0].Permissions == effective) Resolve("ACL");
        else throw new MeshException(role == 0 ? "Odebrání potvrzeno. Načtená část ACL neprokazuje stav celého seznamu; zkontrolujte přístup samostatně." : "Změnu nelze jednoznačně ověřit v načtené části ACL.");
    });
    public Task ReadNeighbours() => Run("Načítám sousedy repeateru…", async () =>
    {
        var c = RequireNode(true); ushort offset = 0; Neighbours.Clear();
        for (int n = 0; n < 128; n++)
        {
            var page = NeighbourPage.Decode(await Session.Binary(c.Key, NeighbourPage.Request(offset, (uint)Random.Shared.NextInt64(1, uint.MaxValue))));
            Neighbours = Neighbours.Concat(page.Entries).DistinctBy(e => e.Key).OrderBy(e => e.SecondsAgo).ToList(); offset += (ushort)page.Entries.Count; Update();
            if (page.Entries.Count == 0 || offset >= page.Total) return;
        }
        throw new MeshException("Limit 128 stránek; seznam sousedů není úplný.");
    });
    private async Task FetchRegions(Contact c)
    {
        List<string> lines = []; foreach (var command in new[] { "region", "region home", "region default" }) { var reply = await Session.Cli(c.Key, command); if (Commands.Error(reply)) throw new MeshException(Clean(reply)); lines.Add(command + "\n" + reply); } RegionText = string.Join("\n\n", lines);
    }
    public Task ReadRegions() => Run("Načítám regiony…", async () => await FetchRegions(RequireNode(true)));
    public Task ChangeRegion(string operation, string name, string parent) => Run("Upravuji regiony…", async () =>
    {
        var c = RequireNode(true); var generation = epoch;
        if (!new[] { "put", "remove", "allowf", "denyf", "home", "default" }.Contains(operation)) throw new MeshException("Neplatná operace regionu.");
        name = Commands.Region(name); if (parent.Length > 0) parent = Commands.Region(parent);
        var command = $"region {operation} {name}" + (operation == "put" && parent.Length > 0 ? " " + parent : "");
        if (!await Confirm("Změnit regiony?", command + "\nMůže omezit přeposílání a vzdálený přístup. Použijte celý přesný název. Poté se odešle region save a načte přehled.")) return;
        StillCurrent(c, generation);
        async Task Exact(string region) { var reply = await Session.Cli(c.Key, "region get " + region); if (Commands.Error(reply) || reply.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() != region) throw new MeshException("Úplný název regionu nebyl potvrzen; zápis se neodešle."); }
        if (operation != "put") await Exact(name); else if (parent.Length > 0) await Exact(parent);
        BeginChange("Regiony · zkontrolujte přehled"); var response = (await Session.Cli(c.Key, command)).Trim();
        var accepted = operation == "home" ? response == "home is now " + name : operation == "default" ? response == "default scope is now " + name : response.StartsWith("OK", StringComparison.OrdinalIgnoreCase);
        if (!accepted) throw new MeshException("Změna regionu nepotvrzena: " + Clean(response));
        if (!(await Session.Cli(c.Key, "region save")).StartsWith("OK", StringComparison.OrdinalIgnoreCase)) throw new MeshException("Trvalé uložení regionů nepotvrzeno.");
        await FetchRegions(c);
    });
    public Task ChangePassword(string password, bool guest, bool remember) => Run("Měním heslo…", async () =>
    {
        var c = RequireNode(true); var generation = epoch; password = Commands.Password(password); secrets.Add(password);
        if (!await Confirm("Změnit " + (guest ? "heslo hosta?" : "heslo správce?"), c.Name + "\nZměna může ovlivnit další přihlášení. Heslo ani odpověď firmware se nezobrazí v konzoli ani diagnostice. Při timeoutu už může být nové heslo nastavené.")) return;
        StillCurrent(c, generation); BeginChange(guest ? "Heslo hosta · ověřte samostatně" : "Heslo správce · ověřte přihlášením");
        var reply = await Session.Cli(c.Key, (guest ? "set guest.password " : "password ") + password);
        if (!(guest ? reply.StartsWith("OK", StringComparison.OrdinalIgnoreCase) : reply == "password now: " + password)) throw new MeshException("Repeater změnu hesla jednoznačně nepotvrdil.");
        if (!guest) { Measurement?.Stop(); adminNode = null; if (remember) credentials.Save(c.Id, password); else credentials.Delete(c.Id); }
        AddLog("Repeater potvrdil změnu hesla; nové přihlášení dosud netestováno");
    });
    public Task Advert(bool zeroHop) => SendCli(zeroHop ? "advert.zerohop" : "advert");
    public Task Restart() => SendCli("reboot");
    public void SetMonitoring(bool enabled)
    {
        bool waiting = Measurement is { InFlight: true, Transmitted: false };
        Measurement?.Stop(); if (waiting) Session.CancelServiceWait();
        if (enabled) { RequireNode(true); if (Busy) throw new MeshException("Počkejte na dokončení operace; měření nebylo spuštěno."); Measurement = new(MeasurementPlan, measurementClock.GetUtcNow()); }
        Update();
    }
    public async Task SetDiagnosticOptions(int interval, int samples)
    {
        if (Monitoring) throw new MeshException("Před změnou plánu zastavte měření.");
        _ = new DiagnosticPlan(interval, samples, MeasurementRoute);
        Options.DiagnosticMinutes = interval; Options.DiagnosticSamples = samples; await SaveLibrary(); Update();
    }
    private async Task DiagnosticTick(DateTimeOffset now)
    {
        if (!Monitoring || Measurement is not { } run) return;
        if (!Admin || Node is not { Stored: true, Kind: 2 } c) { run.Stop(); Update(); return; }
        if (now < run.Started) { run.Stop(); Error = "Systémový čas se posunul zpět; spusťte nové měření až po opravě času."; Update(); return; }
        if (MeasurementRoute == ServiceRoute.FloodOrUnknown && run.Plan.IntervalMinutes < 60) { run.Stop(); Error = "Trasa už není ověřená; nové měření bez trasy vyžaduje nejméně 60 minut."; Update(); return; }
        if (!run.TakeDue(now, Busy)) { Update(); return; }
        var generation = epoch;
        await Run("Diagnostické měření: žádám stav po LoRa…", async () =>
        {
            try { var status = await Session.Status(c.Key, run.MarkTransmitted); StillCurrent(c, generation); if (!ReferenceEquals(Measurement, run)) return; RecordStatus(c, status); run.Finish(true); }
            catch { run.Finish(false); throw; }
        }, () => run.Running && Node is { Stored: true, Kind: 2 } && ReferenceEquals(Measurement, run));
        Update();
    }
    public Task VerifyPending() => Run("Ověřuji čekající změny čtením…", async () =>
    {
        var c = RequireNode(true); foreach (var pending in Operations.Pending.ToArray())
            if (pending.Expected != null && Commands.Keys.Contains(pending.Key)) { var value = await ReadField(c, pending.Key); if (value != null && Commands.Same(pending.Key, value, pending.Expected)) Resolve(pending.Key); }
        AddLog("Čekající konfigurace znovu načtena; ostatní kroky vyžadují samostatnou kontrolu");
    });
    public Task PrepareSetup(bool czech, string owner) => Run("Připravuji prvotní nastavení…", async () =>
    {
        var c = RequireNode(true); var generation = epoch;
        if (owner.Length > 0) owner = Commands.Validate("owner.info", owner);
        if (Settings.Any(f => f.Dirty) && !await Confirm("Nahradit rozepsané návrhy?", "Nejprve se znovu načtou hodnoty z repeateru.")) return;
        StillCurrent(c, generation); SetupSteps.Clear();
        List<string> commands = ["ver", "get flood.advert.interval", "get advert.interval", "get dutycycle", "get path.hash.mode", "get owner.info"];
        foreach (var command in commands) SetupSteps.Add(new(command, "Čeká"));
        for (int i = 0; i < commands.Count; i++)
        {
            StillCurrent(c, generation); string command = commands[i];
            Progress = $"Prvotní nastavení · {i + 1}/{commands.Count} · {command}";
            SetupSummary = "Probíhá pouze čtení po LoRa. Odpověď může kvůli vysílacímu rozpočtu trvat desítky sekund.";
            SetupSteps[i] = new(command, "Čtu · čekám na odpověď"); Update();
            try
            {
                bool supported;
                if (command == "ver") { var reply = await Session.Cli(c.Key, command); supported = !Commands.Error(reply); }
                else supported = await ReadField(c, command[4..]) != null;
                StillCurrent(c, generation); SetupSteps[i] = new(command, supported ? "Načteno" : "Nepodporované / odmítnuto");
                if (command == "get dutycycle" && !supported) { commands.Insert(i + 1, "get af"); SetupSteps.Insert(i + 1, new("get af", "Čeká · náhradní starší příkaz")); }
                AddLog("Prvotní nastavení · " + command + (supported ? " · načteno" : " · odmítnuto / nepodporováno"));
            }
            catch (Exception e)
            {
                // Disconnect clears the collection; never put old results into a new node.
                if (generation == epoch && SelectedNode == c.Id)
                {
                    SetupSteps[i] = new(command, "Selhalo · načítání zastaveno");
                    for (int rest = i + 1; rest < SetupSteps.Count; rest++) SetupSteps[rest] = SetupSteps[rest] with { State = "Neprovedeno" };
                    SetupSummary = "Načítání není dokončené. Návrhy nebyly připraveny a žádná konfigurace nebyla odeslána.";
                    AddLog("Prvotní nastavení · " + command + " · čtení selhalo");
                }
                throw new MeshException($"Prvotní nastavení, krok {i + 1}/{commands.Count} ({command}): " + Clean(e.Message));
            }
        }
        StillCurrent(c, generation);
        var duty = Settings.Single(f => f.Key == "dutycycle");
        Dictionary<string, string> targets = czech ? new() { ["flood.advert.interval"] = "25", ["advert.interval"] = "0", [duty.Actual != null ? "dutycycle" : "af"] = duty.Actual != null ? "10" : "9", ["path.hash.mode"] = "1" } : [];
        if (owner.Length > 0) targets["owner.info"] = owner;
        foreach (var f in Settings) if (f.Actual != null && targets.TryGetValue(f.Key, out var v)) f.Draft = v;
        SetupSummary = SetupSteps.Any(s => s.State == "Nepodporované / odmítnuto") ? "Načítání dokončeno s nepodporovanými položkami. Návrhy obsahují jen načtené hodnoty; zařízení se nezměnilo." : "Načítání dokončeno. Zkontrolujte hodnoty a případné návrhy v Nastavení; zařízení se nezměnilo.";
        AddLog("Prvotní nastavení připraveno jako návrh; zápis vyžaduje výběr a potvrzení");
    });

    public void CaptureSnapshot(string name)
    {
        RequireNode(); var fields = Settings.Where(f => f.Actual != null && f.ReadAt != null && !Operations.Pending.Any(p => p.Key == f.Key)).ToArray();
        if (fields.Any(f => f.Key == "dutycycle")) fields = fields.Where(f => f.Key != "af").ToArray();
        var snapshot = new ConfigSnapshot { Account = Archive!.Account, Node = Node!.Id, Name = name.Length == 0 ? Node.Name : name, Values = fields.ToDictionary(f => f.Key, f => f.Actual!), ReadAt = fields.ToDictionary(f => f.Key, f => f.ReadAt!.Value) }; snapshot.Validate();
        var op = MutableOps(); op.Snapshots.Add(snapshot); op.Snapshots = op.Snapshots.TakeLast(30).ToList(); Persist(); Update();
    }
    public void ImportSnapshot(string json)
    {
        if (json.Length > 1_000_000) throw new MeshException("Příliš velký snímek."); var snapshot = JsonSerializer.Deserialize<ConfigSnapshot>(json, LocalStore.Json) ?? throw new MeshException("Neplatný snímek."); snapshot.Validate();
        if (snapshot.Account != Archive?.Account || snapshot.Node != SelectedNode) throw new MeshException("Snímek patří jinému companionu nebo repeateru.");
        var op = MutableOps(); op.Snapshots.RemoveAll(s => s.Id == snapshot.Id); op.Snapshots.Add(snapshot); op.Snapshots = op.Snapshots.TakeLast(30).ToList(); Persist(); Update();
    }
    public Task Restore(ConfigSnapshot snapshot, string[] keys) => Run("Porovnávám snímek s repeaterem…", async () =>
    {
        var c = RequireNode(true); var generation = epoch; snapshot.Validate();
        if (snapshot.Account != Archive?.Account || snapshot.Node != c.Id || Settings.Any(f => f.Dirty)) throw new MeshException("Cizí snímek nebo rozepsané návrhy. Nejprve návrhy uložte či zahoďte.");
        Dictionary<string, (string Before, string After)> changes = [];
        foreach (var key in keys.Distinct())
        {
            if (!snapshot.Values.TryGetValue(key, out var value)) continue;
            var actual = await ReadField(c, key) ?? throw new MeshException("Čtení selhalo; žádná obnova nebyla odeslána."); if (!Commands.Same(key, actual, value)) changes[key] = (actual, value);
        }
        if (changes.Count == 0) return;
        if (!await Confirm("Obnovit vybrané rozdíly?", string.Join('\n', changes.Select(x => $"{x.Key}: {x.Value.Before} → {x.Value.After}")) + (changes.ContainsKey("radio") ? "\nRádio se použije po restartu a může přerušit spojení s companionem." : "") + "\nPřed zápisem znovu ověřím stav. Restart se automaticky neposílá.")) return;
        StillCurrent(c, generation);
        foreach (var (key, values) in changes) { var now = await Session.Cli(c.Key, "get " + key); if (Commands.Error(now) || !Commands.Same(key, Commands.Value(now), values.Before)) throw new MeshException("Stav se od porovnání změnil; žádný zápis nebyl odeslán."); }
        foreach (var (key, values) in changes) { Settings.Single(f => f.Key == key).Draft = values.After; await WriteSetting(c, key, values.After); }
    });
    public async Task RenameProfile(CompanionProfile profile, string alias) { if (alias.Length > 80) throw new MeshException("Alias nejvýše 80 znaků."); profile.Alias = alias; await SaveLibrary(); Update(); }
    public async Task DeleteProfile(CompanionProfile profile)
    {
        if (Initialized && profile.Account == Archive?.Account) throw new MeshException("Nejprve companion odpojte.");
        if (!await Confirm("Odstranit profil?", "Odstraní se profil, jeho zkratky a evidence. Archiv zpráv a systémová hesla zůstanou lokálně zachované.")) return;
        Library.Profiles.Remove(profile); Library.Shortcuts.RemoveAll(s => s.Account == profile.Account); Library.Evidence.RemoveAll(e => e.Account == profile.Account); Library.Checks.RemoveAll(c => c.Account == profile.Account); await SaveLibrary(); Update();
    }
    public async Task AddShortcut(string title, string command) { if (Archive == null) throw new MeshException("Nejprve připojte companion."); Shortcut shortcut = new(Guid.NewGuid(), Archive.Account, title, command); shortcut.Validate(); Library.Shortcuts.Add(shortcut); await SaveLibrary(); Update(); }
    public async Task DeleteShortcut(Shortcut shortcut) { Library.Shortcuts.Remove(shortcut); await SaveLibrary(); Update(); }
    public async Task RecordCheck(string test, string result)
    {
        if (Archive == null || SelectedNode == null || Device == null || Firmware.Length == 0) throw new MeshException("Nejprve načtěte verze companionu i repeateru.");
        if (!HardwareTests.Contains(test) || !new[] { "Prošlo", "Selhalo", "Neprovedeno" }.Contains(result)) throw new MeshException("Neplatný test.");
        Library.Checks.Add(new(Archive.Account, SelectedNode, Device.Version + " / " + Device.Build, Firmware, Version, RuntimeInformation.OSDescription, RuntimeInformation.OSArchitecture.ToString(), test, result, DateTimeOffset.UtcNow)); Library.Checks = Library.Checks.TakeLast(256).ToList(); await SaveLibrary(); Update();
    }
    public static readonly string[] HardwareTests = ["BLE připojení a systémové párování", "Opětovné připojení a probuzení PC", "Kontakty a příjem advertu", "Přihlášení a načtení konfigurace", "Změna a zpětné ověření konfigurace", "DM a ACK", "Kanál a zachycené přeposílání", "Systémové oznámení", "Restart a synchronizace času"];
    public string DiagnosticReport() => JsonSerializer.Serialize(new
    {
        App = "MeshCore Servicer Windows " + Version, ProtocolCommit = Codec.FirmwareCommit,
        OS = RuntimeInformation.OSDescription, Architecture = RuntimeInformation.OSArchitecture.ToString(),
        CompanionProtocol = Device?.Protocol, CompanionFirmware = Device?.Version, CompanionBuild = Device?.Build,
        Connected = Initialized, NeedsReconnect = Session.RequiresReconnect, StorageProblem = StorageError != null,
        Categories = Log.Select(l => new { l.Date, l.Category }),
        HardwareTests = Library.Checks.Where(c => c.Account == Archive?.Account && c.Node == SelectedNode).Select(c => new { c.CompanionFirmware, c.RepeaterFirmware, c.App, c.Os, c.Architecture, c.Test, c.Result, c.Date })
    }, LocalStore.Json);
}
