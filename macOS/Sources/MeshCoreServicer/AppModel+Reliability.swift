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
    var measurementRoute: ServiceRoute { selected.map { session.route(for:$0.key) } ?? .floodOrUnknown }
    var measurementPlan: DiagnosticPlan? { try? DiagnosticPlan(intervalMinutes:max(monitorIntervalMinutes,measurementRoute.minimumMeasurementMinutes),samples:monitorSampleLimit,route:measurementRoute) }
    func stopMonitoring() {
        monitoring = false; monitorNext = nil; measurement?.stop()
        // An already transmitted request cannot be recalled: let its bounded reply wait finish.
        if measurement?.transmitted != true { monitorTask?.cancel() }
        monitorTask = nil
    }
    func setMonitoring(_ enabled: Bool) {
        stopMonitoring(); guard enabled else { return }
        guard !busy, admin, let c = selected, c.stored, c.kind == 2, let account = selfInfo?.key.hex, let plan = measurementPlan else { error = "Měření vyžaduje správce, neobsazené spojení, 1–6 vzorků a délku nejvýše 6 hodin."; return }
        measurement = DiagnosticMeasurement(plan:plan); monitoring = true
        let run = measurement!.id
        monitorTask = Task { [weak self] in
            while let self, self.monitoring, self.measurement?.id == run, let next = self.measurement?.next {
                self.monitorNext = next
                do { try await Task.sleep(nanoseconds:UInt64(min(Double(plan.intervalMinutes*60),max(0,next.timeIntervalSinceNow))*1e9)) } catch { return }
                guard self.measurement?.id == run else { return }
                guard self.monitoring, self.admin, self.selectedID == c.id, self.selfInfo?.key.hex == account else { self.stopMonitoring(); return }
                await self.monitorTick(contact:c)
            }
        }
    }
    func monitorTick(contact c: Contact, now: Date = Date()) async {
        guard monitoring, admin, selectedID == c.id, selected?.stored == true, selected?.kind == 2 else { stopMonitoring(); return }
        if let started = measurement?.start, now < started { stopMonitoring(); error = "Systémový čas se posunul zpět; spusťte nové měření až po opravě času."; return }
        if measurementRoute == .floodOrUnknown, (measurement?.plan.intervalMinutes ?? 0) < 60 {
            stopMonitoring(); error = "Trasa už není ověřená. Měření zastaveno; nové měření bez trasy vyžaduje nejméně 60 minut."; return
        }
        guard measurement?.takeDue(now:now,busy:busy) == true else {
            monitoring = measurement?.running == true; monitorNext = measurement?.next; return
        }
        busy = true; progress = "Diagnostické měření: žádám stav po LoRa…"
        let generation = connectionGeneration, run = measurement!.id
        defer { busy = false; if measurement?.id == run { monitoring = measurement?.running == true; monitorNext = monitoring ? measurement?.next : nil } }
        do {
            try session.beginServiceOperation { [weak self] in self?.monitoring == true && self?.selected?.stored == true && self?.selected?.kind == 2 && self?.measurement?.id == run && self?.admin == true && self?.selectedID == c.id && self?.connectionGeneration == generation }
            defer { session.endServiceOperation() }
            let status = try await session.status(key:c.key,onSend:{ self.measurement?.markTransmitted() })
            guard generation == connectionGeneration, selectedID == c.id, measurement?.id == run else { return }
            acceptHealth(status,contact:c); measurement?.finish(success:true); progress = "Diagnostický vzorek uložen"
        } catch {
            if measurement?.id == run { measurement?.finish(success:false); stopMonitoring() }
            if error is ServiceOperationCancelled || error is CancellationError && !monitoring { progress = "Měření zastaveno před odesláním"; return }
            self.error = clean(error.localizedDescription); progress = "Měření zastaveno po chybě"; log("Diagnostické měření zastaveno; žádné automatické opakování.",level:.warning)
        }
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
