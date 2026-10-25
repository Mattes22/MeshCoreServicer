import AppKit
import UniformTypeIdentifiers
import MeshCoreKit

struct SnapshotComparison: Identifiable {
    let id = UUID()
    let snapshot: ConfigSnapshot
    let generation: UUID
    let current: [String:String]
    let proposed: [String:String]
    var keys: [String] { CLIValidation.keys.filter { proposed[$0] != nil } }
}
extension AppModel {
    static func readOnlyCLI(_ text: String) -> Bool {
        let t = text.lowercased().trimmingCharacters(in:.whitespaces)
        return t.hasPrefix("get ") || ["ver","board","clock","neighbors","region","region home","region default","sensor list"].contains(t) || t.hasPrefix("region get ") || t.hasPrefix("region list ") || t.hasPrefix("sensor get ")
    }
    func acceptHealth(_ status: RepeaterStatus, contact c: Contact) {
        stats = status; statsDate = Date(); verified[c.id] = Date(); operations.record(status,repeater:c.id)
    }
    func stopMonitoring() { monitorTask?.cancel(); monitorTask = nil; monitoring = false; monitorNext = nil }
    func setMonitoring(_ enabled: Bool) {
        stopMonitoring(); guard enabled else { return }
        guard admin, let c = selected, c.stored, let account = selfInfo?.key.hex, (5...1440).contains(monitorIntervalMinutes) else { error = "Monitoring vyžaduje připojení, správce a interval 5–1440 minut."; return }
        monitoring = true
        let interval = UInt64(monitorIntervalMinutes)*60
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.monitorNext = Date().addingTimeInterval(Double(interval))
                do { try await Task.sleep(nanoseconds:interval*1_000_000_000) } catch { return }
                guard let self, self.monitoring, self.admin, self.selectedID == c.id, self.selfInfo?.key.hex == account else { self?.stopMonitoring(); return }
                await self.monitorTick(contact:c)
            }
        }
    }
    func monitorTick(contact c: Contact) async {
        guard monitoring, admin, !busy, selectedID == c.id else { return }
        busy = true; progress = "Monitor: načítám stav repeateru po LoRa…"
        defer { busy = false }
        do { let status = try await session.status(key:c.key); acceptHealth(status,contact:c); progress = "Monitoring: stav uložen" }
        catch { stopMonitoring(); self.error = clean(error.localizedDescription); progress = "Monitoring zastaven po chybě"; log("Monitoring zastaven; požadavek nebude automaticky opakován.",level:.warning) }
    }
    func captureSnapshot(name: String) {
        guard let c = selected, let account = selfInfo?.key.hex, account == operations.document?.account, !busy else { return }
        do {
            let uncertain = Set(operations.current.unverified.map(\.key))
            var values = config.filter { key,value in
                !uncertain.contains(key) && configDates[key] != nil && (try? CLIValidation.validate(key:key,value:value)) != nil && ![FieldState.sending,.verifying,.uncertain,.failed].contains(fieldStates[key] ?? .confirmed)
            }
            if values["dutycycle"] != nil { values["af"] = nil }
            let dates = configDates.filter { values[$0.key] != nil }
            let snapshot = try ConfigSnapshot(account:account,repeater:c.id,name:name.isEmpty ? c.name : name,values:values,readAt:dates)
            try operations.addSnapshot(snapshot); notice = "Snímek načtených hodnot uložen. Neobsahuje hesla ani soukromé klíče."
        } catch { self.error = error.localizedDescription }
    }
    func compareSnapshot(_ snapshot: ConfigSnapshot, keys: Set<String>) {
        guard admin, !busy, let c = selected else { return }
        do {
            try snapshot.validate()
            guard snapshot.account == selfInfo?.key.hex, snapshot.repeater == c.id else { throw MeshError.invalid("snímek patří jinému companionu nebo repeateru") }
            guard dirtyKeys.isEmpty else { throw MeshError.invalid("nejprve uložte nebo zahoďte rozepsané změny v Nastavení") }
            let selected = CLIValidation.keys.filter { keys.contains($0) && snapshot.values[$0] != nil }
            guard !selected.isEmpty else { throw MeshError.invalid("vyberte alespoň jednu hodnotu snímku") }
            restorePreview = nil
            perform("Porovnávám snímek se skutečným stavem…") {
                var current: [String:String] = [:], proposed: [String:String] = [:]
                for key in selected {
                    let reply = try await self.session.cli(key:c.key,command:"get \(key)")
                    guard !CLIValidation.isErrorReply(reply) else { throw MeshError.remote("Čtení \(key) selhalo; žádná obnova nebyla odeslána.") }
                    let actual = Self.cliValue(reply), desired = snapshot.values[key]!
                    current[key] = actual; self.config[key] = actual; self.edits[key] = actual; self.configDates[key] = Date()
                    if !MeshPresentation.sameValue(key:key,actual,desired) { proposed[key] = desired }
                }
                self.restorePreview = SnapshotComparison(snapshot:snapshot,generation:self.connectionGeneration,current:current,proposed:proposed)
                if proposed.isEmpty { self.notice = "Vybrané hodnoty snímku už odpovídají repeateru." }
            }
        } catch { self.error = error.localizedDescription }
    }
    func restoreSnapshot() {
        guard admin, !busy, let c = selected, let preview = restorePreview, !preview.proposed.isEmpty,
              preview.generation == connectionGeneration, preview.snapshot.repeater == c.id, preview.snapshot.account == selfInfo?.key.hex else { return }
        let summary = preview.keys.map { "\($0): \(preview.current[$0] ?? "—") → \(preview.proposed[$0]!)" }.joined(separator:"\n")
        let radio = preview.proposed["radio"] != nil ? "\nRádio se použije po restartu a může přerušit LoRa spojení. Zajistěte odpovídající nastavení companionu." : ""
        confirmation = Confirmation(title:"Obnovit vybrané hodnoty snímku?",message:"\(c.name)\n\(summary)\(radio)\n\nPřed zápisem znovu ověřím stav. Změny se provedou sekvenčně se zpětným čtením, při chybě se zastaví. Restart se automaticky neposílá.",action:{
            guard self.admin, self.selectedID == c.id, self.selfInfo?.key.hex == preview.snapshot.account, self.connectionGeneration == preview.generation, self.dirtyKeys.isEmpty else { return }
            self.perform("Obnovuji vybrané hodnoty snímku…") {
                for key in preview.keys {
                    let reply = try await self.session.cli(key:c.key,command:"get \(key)")
                    guard !CLIValidation.isErrorReply(reply), MeshPresentation.sameValue(key:key,Self.cliValue(reply),preview.current[key]!) else { throw MeshError.remote("Stav \(key) se od porovnání změnil. Žádný zápis nebyl odeslán; porovnejte snímek znovu.") }
                }
                self.totalSteps = preview.keys.count
                for key in preview.keys {
                    let value = try CLIValidation.validate(key:key,value:preview.proposed[key]!)
                    self.edits[key] = value; try await self.writeSetting(key:key,value:value,contact:c); self.completedSteps += 1
                }
                self.restorePreview = nil; self.notice = "Vybrané hodnoty snímku byly potvrzeny a ověřeny."
            }
        })
    }
    func exportSnapshot(_ snapshot: ConfigSnapshot) {
        do { try snapshot.validate() } catch { self.error = error.localizedDescription; return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "MeshCore-snímek.json"
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; encoder.dateEncodingStrategy = .iso8601; try encoder.encode(snapshot).write(to:url,options:.atomic) }
            catch { self?.error = "Export snímku selhal." }
        }
    }
    func importSnapshot() {
        guard !busy, let account = operations.document?.account, let repeater = operations.selectedID else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url, let self else { return }
            do {
                guard try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0 <= 1_000_000 else { throw MeshError.invalid("soubor snímku je příliš velký") }
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                let snapshot = try decoder.decode(ConfigSnapshot.self,from:Data(contentsOf:url)); try snapshot.validate()
                guard self.operations.document?.account == account, self.operations.selectedID == repeater, snapshot.account == account, snapshot.repeater == repeater else { throw MeshError.invalid("soubor patří jinému companionu nebo repeateru") }
                try self.operations.addSnapshot(snapshot); self.notice = "Snímek importován. Nic se do repeateru nezapsalo."
            } catch { self.error = "Import snímku selhal: \(error.localizedDescription)" }
        }
    }
}
