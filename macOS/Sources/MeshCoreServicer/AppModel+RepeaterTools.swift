import Foundation
import MeshCoreKit

struct RepeaterToolsState {
    var firmware: String?
    var board: String?
    var clock: String?
    var clockRead: Date?
    var clockResult: String?
    var telemetry: TelemetryReport?
    var telemetryDate: Date?
    var access: [AccessEntry] = []
    var accessDate: Date?
    var neighbours: [RepeaterNeighbour] = []
    var neighbourTotal = 0
    var neighbourDate: Date?
    var regionDump: String?
    var regionHome: String?
    var regionDefault: String?
    var regionResult: String?
    var passwordResult: String?
    var communityLoaded = false
    var communitySnapshot: [String:String] = [:]
    var communitySelected: Set<String> = []
    var communityDutyKey: String?
    var communityOwner = ""
    var communitySyncClock = false
    var useCzechProfile = false
}

extension AppModel {
    var communitySettings: [CommunitySetting] {
        CommunitySetting.recommended(dutyKey:tools.communityDutyKey,owner:tools.communityOwner).map { setting in
            CommunitySetting(key:setting.key,title:setting.title,target:setting.key == "owner.info" ? tools.communityOwner : (tools.useCzechProfile ? setting.target : tools.communitySnapshot[setting.key] ?? ""))
        }
    }
    func chooseSetupProfile(czech: Bool) {
        guard !busy else { return }
        tools.useCzechProfile = czech
        tools.communitySelected = []
        // Choosing a profile prepares differences only; it never sends a packet.
        if czech && tools.communityLoaded {
            tools.communitySelected = Set(communitySettings.filter { setting in
                guard let current = tools.communitySnapshot[setting.key], !setting.target.isEmpty else { return false }
                return !MeshPresentation.sameValue(key:setting.key,current,setting.target)
            }.map(\.key))
        }
    }
    func writeSetting(key: String, value: String, contact c: Contact) async throws {
        operations.beginChange(key,repeater:c.id,expected:value)
        progress = "Ukládám \(key)…"; fieldStates[key] = .sending; fieldErrors[key] = nil
        do {
            let reply = try await session.cli(key:c.key,command:"set \(key) \(value)")
            guard reply.uppercased().hasPrefix("OK") else { throw MeshError.remote("Repeater změnu nepotvrdil: \(clean(reply))") }
            fieldStates[key] = .verifying
            if key == "radio" { restartRequired = true; operations.beginChange("Rádio · vyžaduje restart",repeater:c.id) }
            let check = try await session.cli(key:c.key,command:"get \(key)")
            guard !CLIValidation.isErrorReply(check) else { throw MeshError.remote("Změna potvrzena, zpětné načtení selhalo.") }
            let actual = Self.cliValue(check)
            config[key] = actual; configDates[key] = Date(); verified[c.id] = Date()
            if MeshPresentation.sameValue(key:key,actual,value) {
                edits[key] = actual; fieldStates[key] = .confirmed; operations.verifiedChange(key,repeater:c.id)
            } else {
                fieldStates[key] = .different
                fieldErrors[key] = "Repeater vrátil jinou hodnotu. Načteno: \(actual). Rozepsaná hodnota zůstala zachována."
                throw MeshError.remote("U nastavení \(key) se zpětně načtená hodnota liší. Další změny nebyly odeslány.")
            }
            if tools.communityLoaded { tools.communitySnapshot[key] = actual }
            // These are two views of the same firmware field; discard a stale alternate reading.
            let alternate = key == "dutycycle" ? "af" : (key == "af" ? "dutycycle" : nil)
            if let alternate { config[alternate] = nil; edits[alternate] = nil; configDates[alternate] = nil; fieldStates[alternate] = nil }
            log("Změna \(key) potvrzena a ověřena zpětným čtením.")
        } catch {
            if fieldStates[key] != .different {
                fieldStates[key] = fieldStates[key] == .verifying ? .uncertain : .failed
                fieldErrors[key] = clean(error.localizedDescription)
            }
            throw error
        }
    }
    func loadCommunitySetup() {
        guard admin, !busy, let c = selected else { return }
        let action = { self.perform("Načítám podklady pro prvotní nastavení…") {
            self.tools.communityLoaded = false; self.tools.communitySelected = []; self.tools.communitySnapshot = [:]
            let ver = try await self.session.cli(key:c.key,command:"ver")
            if !CLIValidation.isErrorReply(ver) { self.tools.firmware = ver }
            var keys = ["flood.advert.interval","advert.interval","dutycycle","path.hash.mode","owner.info"]
            self.totalSteps = keys.count
            while !keys.isEmpty {
                let key = keys.removeFirst(); self.progress = "Načítám \(key)…"
                let reply = try await self.session.cli(key:c.key,command:"get \(key)")
                if CLIValidation.isErrorReply(reply) {
                    self.fieldStates[key] = .unsupported; self.fieldErrors[key] = self.clean(reply)
                    self.config[key] = nil; self.edits[key] = nil
                    if key == "dutycycle" { keys.insert("af",at:0); self.totalSteps += 1 }
                } else {
                    let actual = Self.cliValue(reply)
                    self.tools.communitySnapshot[key] = actual; self.config[key] = actual; self.edits[key] = actual
                    self.configDates[key] = Date(); self.fieldStates[key] = .confirmed; self.fieldErrors[key] = nil
                }
                self.completedSteps += 1
            }
            self.tools.communityDutyKey = self.tools.communitySnapshot["dutycycle"] != nil ? "dutycycle" : (self.tools.communitySnapshot["af"] != nil ? "af" : nil)
            if self.tools.communityOwner.isEmpty { self.tools.communityOwner = self.tools.communitySnapshot["owner.info"] ?? "" }
            self.tools.communityLoaded = true
            self.tools.communitySelected = Set(self.communitySettings.filter { setting in
                guard let current = self.tools.communitySnapshot[setting.key], !setting.target.isEmpty else { return false }
                return !MeshPresentation.sameValue(key:setting.key,current,setting.target)
            }.map(\.key))
            self.verified[c.id] = Date()
            self.notice = "Současné nastavení načteno. Vyberte změny a zkontrolujte je před zápisem."
        } }
        if !dirtyKeys.isEmpty { confirmation = Confirmation(title:"Načíst průvodce a nahradit rozepsané hodnoty?",message:"Čtení nahradí návrhy intervalů, duty cycle, hashů cesty a kontaktu vlastníka hodnotami z repeateru.",action:action) } else { action() }
    }
    func applyCommunitySetup() {
        guard admin, !busy, tools.communityLoaded, let c = selected else { return }
        do {
            let changes = try communitySettings.filter { tools.communitySelected.contains($0.key) }.compactMap { setting -> (String,String)? in
                guard let current = tools.communitySnapshot[setting.key] else { throw MeshError.invalid("nejprve načtěte podporu \(setting.key)") }
                let value = try CLIValidation.validate(key:setting.key,value:setting.target)
                return MeshPresentation.sameValue(key:setting.key,current,value) ? nil : (setting.key,value)
            }
            let sync = tools.communitySyncClock
            guard !changes.isEmpty || sync else { notice = "Nejsou vybrané žádné rozdílné hodnoty ani synchronizace hodin."; return }
            let summary = changes.map { "\($0.0): \(tools.communitySnapshot[$0.0] ?? "—") → \($0.1)" }.joined(separator:"\n")
            confirmation = Confirmation(title:"Použít vybrané nastavení na \(c.name)?",message:summary + (sync ? "\nHodiny: synchronizovat podle času Macu (UTC)." : "") + "\n\nZměny proběhnou postupně se zpětným čtením. Při chybě se postup zastaví. Rádio, identita ani hesla se nemění. Komunitní profil je volitelná předvolba, nikoliv univerzální nastavení sítě.",action:{
                guard self.admin, self.selectedID == c.id else { return }
                self.perform("Provádím vybrané prvotní nastavení…") {
                    self.totalSteps = changes.count + (sync ? 1 : 0)
                    for (key,value) in changes {
                        self.edits[key] = value
                        try await self.writeSetting(key:key,value:value,contact:c)
                        self.tools.communitySelected.remove(key); self.completedSteps += 1
                    }
                    if sync { try await self.synchronizeClock(contact:c); self.completedSteps += 1 }
                    self.notice = "Vybrané kroky byly potvrzeny. Hodiny po restartu znovu zkontrolujte a případně synchronizujte."
                }
            })
        } catch { self.error = error.localizedDescription }
    }
    func readRepeaterInfo() {
        guard admin, !busy, let c = selected else { return }
        perform("Načítám verzi a hodiny…") {
            for command in ["ver","board","clock"] {
                let reply = try await self.session.cli(key:c.key,command:command)
                guard !CLIValidation.isErrorReply(reply) else { throw MeshError.remote(self.clean(reply)) }
                if command == "ver" { self.tools.firmware = reply }
                if command == "board" { self.tools.board = reply }
                if command == "clock" { self.tools.clock = reply; self.tools.clockRead = Date(); self.operations.clockChecked(repeater:c.id,text:reply) }
            }
            self.verified[c.id] = Date()
        }
    }
    func syncRepeaterClock() {
        guard admin, !busy, let c = selected else { return }
        confirmation = Confirmation(title:"Synchronizovat hodiny repeateru?",message:"\(c.name) převezme aktuální Unix čas z tohoto Macu. Zkontrolujte správné systémové datum. Firmware čas neposouvá zpět; synchronizaci po restartu opakujte ručně.",action:{
            guard self.admin, self.selectedID == c.id else { return }
            self.perform("Synchronizuji hodiny…") { try await self.synchronizeClock(contact:c) }
        })
    }
    func synchronizeClock(contact c: Contact) async throws {
        operations.beginChange("Hodiny",repeater:c.id)
        tools.clockResult = "Odesílám čas Macu…"
        do {
            // Build immediately before send, not when the confirmation was opened.
            let epoch = UInt32(clamping:Int64(Date().timeIntervalSince1970))
            let reply = try await session.cli(key:c.key,command:"time \(epoch)")
            guard reply.uppercased().hasPrefix("OK") else { throw MeshError.remote(clean(reply)) }
            tools.clockResult = "Repeater potvrdil nastavení času. Ověřuji hodiny…"
            let check = try await session.cli(key:c.key,command:"clock")
            guard !CLIValidation.isErrorReply(check) else { throw MeshError.remote("Nastavení času potvrzeno, zpětné čtení hodin selhalo.") }
            tools.clock = check; tools.clockRead = Date(); verified[c.id] = Date()
            guard let readTime = RepeaterCommand.clockDate(check.trimmingCharacters(in:.whitespacesAndNewlines)), readTime.timeIntervalSince1970 >= Double(epoch)-60, readTime <= Date().addingTimeInterval(60) else { throw MeshError.remote("Repeater nastavení potvrdil, ale načtené hodiny neodpovídají očekávanému času Macu. Zkontrolujte údaj UTC.") }
            operations.clockChecked(repeater:c.id,text:check); operations.verifiedChange("Hodiny",repeater:c.id)
            tools.clockResult = "Nastavení potvrzeno; zpětně načteno: \(check)"
            log("Repeater potvrdil synchronizaci času; hodiny byly znovu načteny.")
        } catch { tools.clockResult = "Synchronizace nebyla plně ověřena: \(clean(error.localizedDescription))"; throw error }
    }
    func readTelemetry() {
        guard admin, !busy, let c = selected else { return }
        perform("Načítám telemetrii repeateru…") {
            let raw = try await self.session.binary(key:c.key,payload:Data([3,0,0,0]))
            self.tools.telemetry = try TelemetryReport.decode(raw); self.tools.telemetryDate = Date(); self.verified[c.id] = Date()
        }
    }
    func readAccess() {
        guard admin, !busy, let c = selected else { return }
        perform("Načítám oprávnění z repeateru…") { try await self.fetchAccess(contact:c) }
    }
    private func fetchAccess(contact c: Contact) async throws {
        let raw = try await session.binary(key:c.key,payload:Data([5,0,0]))
        tools.access = try AccessEntry.decode(raw); tools.accessDate = Date(); verified[c.id] = Date()
    }
    func changeAccess(publicKey: String, permissions: UInt8) {
        guard admin, !busy, let c = selected else { return }
        do {
            let key = try RepeaterCommand.publicKey(publicKey)
            guard permissions <= 3 else { throw MeshError.invalid("oprávnění ACL") }
            guard !(selfInfo?.key.hex == key && permissions != 3) else { throw MeshError.invalid("vlastnímu companionu nelze v tomto formuláři odebrat správu") }
            let existing = tools.access.filter { $0.prefix.hex == String(key.prefix(12)) }
            guard existing.count <= 1 else { throw MeshError.invalid("nejednoznačný prefix v ACL") }
            let effective = permissions == 0 ? 0 : ((existing.first?.permissions ?? 0) & 0xfc) | permissions
            confirmation = Confirmation(title:"Změnit oprávnění přístupu?",message:"Repeater: \(c.name)\nVeřejný klíč: \(key)\nRole: \(permissions) (0 = odebrání, 3 = správce).\nCelý byte oprávnění: \(effective). Načtené doplňkové příznaky se zachovají.\nZměna může ovlivnit vzdálený přístup. ACL se po odpovědi znovu načte; odpověď obsahuje jen šestibajtové prefixy a může být oříznutá.",action:{
                guard self.admin, self.selectedID == c.id else { return }
                self.perform("Měním oprávnění…") {
                    self.operations.beginChange("ACL",repeater:c.id)
                    let reply = try await self.session.cli(key:c.key,command:"setperm \(key) \(effective)")
                    guard reply.uppercased().hasPrefix("OK") else { throw MeshError.remote(self.clean(reply)) }
                    self.notice = "Repeater potvrdil změnu ACL; ověřuji seznam."
                    try await self.fetchAccess(contact:c)
                    let matches = self.tools.access.filter { $0.prefix.hex == String(key.prefix(12)) }
                    if permissions == 0 {
                        guard matches.isEmpty else { throw MeshError.remote("Odebrání potvrzeno, ale prefix se v načtené části ACL stále vyskytuje.") }
                        self.notice = "Odebrání potvrzeno. Prefix není v načtené části ACL; seznam nemusí být úplný."
                    } else {
                        guard matches.count == 1, matches[0].permissions == effective else { throw MeshError.remote("Změna potvrzena, ale v načtené části ACL ji nelze jednoznačně ověřit.") }
                        self.notice = "Změna potvrzena a role ověřena podle šestibajtového prefixu v ACL."; self.operations.verifiedChange("ACL",repeater:c.id)
                    }
                }
            })
        } catch { self.error = error.localizedDescription }
    }
    func readNeighbours() {
        guard admin, !busy, let c = selected else { return }
        perform("Načítám sousedy repeateru…") {
            var entries: [RepeaterNeighbour] = [], offset: UInt16 = 0
            self.tools.neighbourDate = nil
            for _ in 0..<128 {
                let raw = try await self.session.binary(key:c.key,payload:NeighbourPage.request(offset:offset,nonce:UInt32.random(in:1...UInt32.max)))
                let page = try NeighbourPage.decode(raw); self.tools.neighbourTotal = page.total
                entries.append(contentsOf:page.entries); offset += UInt16(page.entries.count)
                self.tools.neighbours = Array(Dictionary(entries.map { ($0.id,$0) },uniquingKeysWith:{ _,new in new }).values).sorted { $0.heardSecondsAgo < $1.heardSecondsAgo }
                if page.entries.isEmpty || Int(offset) >= page.total { self.tools.neighbourDate = Date(); self.verified[c.id] = Date(); return }
            }
            throw MeshError.remote("Seznam sousedů překročil limit načítání. Zobrazená část není úplná.")
        }
    }
    func readRegions() {
        guard admin, !busy, let c = selected else { return }
        perform("Načítám regiony…") { try await self.fetchRegions(contact:c) }
    }
    private func fetchRegions(contact c: Contact) async throws {
        for command in ["region","region home","region default"] {
            let reply = try await session.cli(key:c.key,command:command)
            guard !CLIValidation.isErrorReply(reply) else { throw MeshError.remote(clean(reply)) }
            if command == "region" { tools.regionDump = reply }
            if command == "region home" { tools.regionHome = reply }
            if command == "region default" { tools.regionDefault = reply }
        }
        verified[c.id] = Date()
    }
    func changeRegion(operation: String, name: String, parent: String) {
        guard admin, !busy, let c = selected else { return }
        do {
            guard ["put","remove","allowf","denyf","home","default"].contains(operation) else { throw MeshError.invalid("operace regionu") }
            let region = try RepeaterCommand.regionName(name,allowWildcard:true)
            let ancestor = parent.isEmpty ? "" : " " + (try RepeaterCommand.regionName(parent,allowWildcard:true))
            let command = "region \(operation) \(region)" + (operation == "put" ? ancestor : "")
            confirmation = Confirmation(title:"Změnit regiony repeateru?",message:"\(c.name)\n\(command)\n\nZměna může omezit přeposílání a vzdálený přístup. Následně se odešle region save a znovu načte přehled. Firmware u některých operací vybírá první shodu prefixu; použijte přesný úplný název a předem ověřte regiony.",action:{
                guard self.admin, self.selectedID == c.id else { return }
                self.perform("Upravuji regiony…") {
                    self.tools.regionResult = "Odesílám změnu…"
                    if operation == "put", !parent.isEmpty {
                        let probe = try await self.session.cli(key:c.key,command:"region get \(parent)")
                        guard !CLIValidation.isErrorReply(probe), probe.split(whereSeparator:{$0.isWhitespace}).first.map(String.init) == parent else { throw MeshError.remote("Rodičovský region nebyl jednoznačně potvrzen. Změna nebyla odeslána.") }
                    }
                    // Firmware lookup accepts prefixes. Refuse to mutate a different first match.
                    if operation != "put" {
                        let probe = try await self.session.cli(key:c.key,command:"region get \(region)")
                        if CLIValidation.isErrorReply(probe) {
                            guard operation == "default" else { throw MeshError.remote(self.clean(probe)) }
                        } else {
                            guard probe.split(whereSeparator:{$0.isWhitespace}).first.map(String.init) == region else { throw MeshError.remote("Název odpovídá prefixu jiného regionu. Změna nebyla odeslána.") }
                        }
                    }
                    self.operations.beginChange("Regiony · zkontrolujte přehled",repeater:c.id)
                    let reply = try await self.session.cli(key:c.key,command:command)
                    let normalized = reply.trimmingCharacters(in:.whitespacesAndNewlines)
                    let accepted = operation == "home" ? normalized == "home is now \(region)" : (operation == "default" ? normalized == "default scope is now \(region)" : normalized.uppercased().hasPrefix("OK"))
                    guard accepted else { throw MeshError.remote("Změna regionu nebyla potvrzena: \(self.clean(reply))") }
                    self.tools.regionResult = "Repeater odpověděl: \(reply). Ukládám regiony…"
                    let saved = try await self.session.cli(key:c.key,command:"region save")
                    guard saved.uppercased().hasPrefix("OK") else { throw MeshError.remote("Změna přijata, trvalé uložení regionů nebylo potvrzeno.") }
                    self.tools.regionResult = "Změna i trvalé uložení potvrzeny. Načítám přehled…"
                    try await self.fetchRegions(contact:c)
                    self.tools.regionResult = "Změna i uložení potvrzeny; přehled byl znovu načten. Zkontrolujte odpovídající region."
                }
            })
        } catch { self.error = error.localizedDescription }
    }
    func changeRemotePassword(_ newPassword: String, guest: Bool, saveToKeychain: Bool) {
        guard admin, !busy, let c = selected else { return }
        do {
            let secret = try RepeaterCommand.password(newPassword)
            knownSecrets.insert(secret)
            confirmation = Confirmation(title:guest ? "Změnit heslo hosta?" : "Změnit heslo správce?",message:"Repeater: \(c.name)\nNové heslo se odešle po zabezpečené BLE a šifrovaném LoRa spojení. Změna správce může ovlivnit příští přihlášení. Heslo ani odpověď, kterou jej firmware vrací, se nezobrazí v konzoli a diagnostice. Změna vyžaduje odpověď repeateru.",action:{
                guard self.admin, self.selectedID == c.id else { return }
                self.perform("Měním heslo repeateru…") {
                    self.operations.beginChange(guest ? "Heslo hosta · ověřte samostatně" : "Heslo správce · ověřte přihlášením",repeater:c.id)
                    self.tools.passwordResult = "Čekám na potvrzení změny hesla…"
                    var remoteConfirmed = false
                    do {
                    let reply = try await self.session.cli(key:c.key,command:guest ? "set guest.password \(secret)" : "password \(secret)")
                    let confirmed = guest ? reply.uppercased().hasPrefix("OK") : reply == "password now: " + secret
                    guard confirmed else { self.tools.passwordResult = "Výsledek změny hesla není ověřený."; throw MeshError.remote("Repeater změnu hesla jednoznačně nepotvrdil.") }
                    remoteConfirmed = true
                    self.tools.passwordResult = "Repeater potvrdil změnu \(guest ? "hesla hosta" : "hesla správce"). Nové přihlášení zatím nebylo testováno."
                    if !guest {
                        self.adminID = nil
                        if saveToKeychain { try KeychainStore.save(secret,key:c.id) }
                        else { try KeychainStore.delete(c.id) }
                    }
                    self.notice = self.tools.passwordResult
                    self.log("Repeater potvrdil změnu hesla; obsah byl skryt.")
                    } catch {
                        self.tools.passwordResult = remoteConfirmed ? "Repeater změnu hesla potvrdil, ale operace Klíčenky selhala. Pro příští přihlášení použijte nové heslo." : "Změna nebyla plně dokončena. Zkontrolujte chybu; při timeoutu může být nové heslo již nastavené."
                        throw error
                    }
                }
            })
        } catch { self.error = error.localizedDescription }
    }
}
