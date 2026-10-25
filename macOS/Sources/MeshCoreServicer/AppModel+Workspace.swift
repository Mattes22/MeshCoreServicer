import AppKit
import UniformTypeIdentifiers
import MeshCoreKit

extension AppModel {
    static var appVersion: String { Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.7.0" }
    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
    func saveProfilePreferences() {
        var options = preferences.deviceOptions; options.monitorMinutes = monitorIntervalMinutes
        if library.account == nil { initialDeviceOptions = options }
        else { library.updateOptions(options) }
    }
    @discardableResult func activateProfile(_ info: SelfInfo) -> Bool {
        if let expected = requestedProfileID, expected != info.key.hex {
            requestedProfileID = nil; ble.disconnect()
            error = "Bluetooth zařízení má jinou veřejnou identitu než vybraný profil. Připojení bylo ukončeno; vyberte zařízení znovu podle skutečné identity."
            return false
        }
        do {
            let profile = try library.activate(account:info.key.hex,name:info.name,bluetoothID:ble.connectedIdentifier,defaults:initialDeviceOptions)
            if let old = consoleAccount, old != profile.id {
                selectedID = nil; contacts = []; console = []; command = ""; history = []; verified = [:]; advertReceived = [:]; discovered = [:]
                logs = []; knownSecrets = []
                adminID = nil; stopMonitoring()
            }
            consoleAccount = profile.id
            preferences.apply(profile.options); monitorIntervalMinutes = profile.options.monitorMinutes
            requestedProfileID = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func scanCompanions() { requestedProfileID = nil; ble.scan() }
    func connectDevice(_ id: UUID) { requestedProfileID = nil; ble.connect(id) }
    func connectProfile(_ profile: CompanionProfile) {
        guard !busy, !ble.connecting else { return }
        guard let id = profile.bluetoothID else { notice = "Profil nemá uloženou BLE adresu. Vyberte zařízení pomocí skenování."; return }
        guard library.account != profile.id || !ble.ready else { notice = "Tento profil je právě připojený."; return }
        let action = {
            self.ble.disconnect(); self.library.deactivate(); self.preferences.apply(profile.options)
            self.requestedProfileID = profile.id; self.ble.connect(id)
        }
        if ble.ready || !dirtyKeys.isEmpty {
            confirmation = Confirmation(title:"Přepnout na jiný companion?",message:"Aktuální BLE relace se ukončí. Rozepsané změny repeateru se zahodí, přihlášení správce a monitoring se neobnoví. Nové zařízení se ověří podle veřejné identity.",action:action)
        } else { action() }
    }
    var evidenceFirmware: String {
        let raw = tools.firmware?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
        return raw.utf8.count <= 200 && DiagnosticReport.version(raw) != "Nenačteno / neuvedeno" ? raw : ""
    }
    func observeCLI(key: Data,command: String,reply: String) {
        guard key.hex == selectedID else { return }
        if command == "ver", !CLIValidation.isErrorReply(reply) { tools.firmware = clean(String(reply.prefix(120))) }
        guard let account = library.account, let entry = ConsoleCatalog.entry(for:command) else { return }
        library.record(CommandEvidence(account:account,repeater:key.hex,firmware:evidenceFirmware,session:connectionGeneration,command:entry.command,reply:reply))
    }
    func evidence(for command: String) -> CommandEvidence? {
        guard let id = selectedID else { return nil }
        return library.support(command:command,repeater:id,firmware:evidenceFirmware,session:connectionGeneration)
    }
    func verifyChange(_ change: UnverifiedChange) {
        guard admin, !busy, let c = selected, operations.current.unverified.contains(where:{$0.id == change.id}) else { return }
        guard !session.requiresReconnect else { error = MeshError.uncertain.localizedDescription; return }
        let generation = connectionGeneration
        perform("Ověřuji stav po nejasném výsledku…") {
            let action = VerificationAction(key:change.key)
            switch action {
            case .setting(let key):
                let reply = try await self.session.cli(key:c.key,command:"get \(key)")
                guard self.connectionGeneration == generation, self.selectedID == c.id else { throw MeshError.disconnected }
                guard !CLIValidation.isErrorReply(reply) else { throw MeshError.remote("Kontrolní čtení bylo odmítnuto. Položka zůstává neověřená.") }
                let actual = Self.cliValue(reply)
                self.config[key] = actual; self.configDates[key] = Date()
                if let expected = change.expected, MeshPresentation.sameValue(key:key,actual,expected) {
                    self.operations.verifiedChange(key,repeater:c.id); self.fieldStates[key] = .confirmed
                    self.fieldErrors[key] = nil
                    self.notice = "Aktuálně načtená hodnota \(key) odpovídá zamýšlené změně."
                } else {
                    self.notice = change.expected == nil ? "Stav byl načten, ale u staršího záznamu chybí zamýšlená hodnota. Porovnejte jej ručně." : "Načtená hodnota se liší od zamýšlené. Záznam zůstává neověřený; žádný zápis se neopakoval."
                    self.fieldStates[key] = change.expected == nil ? .uncertain : .different
                    self.fieldErrors[key] = change.expected == nil ? "Původní zamýšlená hodnota nebyla zaznamenána." : "Kontrolní čtení vrátilo jinou hodnotu."
                }
            case .radio:
                let reply = try await self.session.cli(key:c.key,command:"get radio")
                guard self.connectionGeneration == generation, self.selectedID == c.id else { throw MeshError.disconnected }
                guard !CLIValidation.isErrorReply(reply) else { throw MeshError.remote("Čtení uloženého rádia selhalo.") }
                self.config["radio"] = Self.cliValue(reply); self.configDates["radio"] = Date()
                self.notice = "Načteno uložené rádio. To nepotvrzuje aktivní rádio po restartu; kontrola zůstává otevřená."
            case .clock:
                let reply = try await self.session.cli(key:c.key,command:"clock")
                guard self.connectionGeneration == generation, self.selectedID == c.id else { throw MeshError.disconnected }
                guard let date = RepeaterCommand.clockDate(reply.trimmingCharacters(in:.whitespacesAndNewlines)) else { throw MeshError.remote("Hodiny se nepodařilo přečíst.") }
                self.tools.clock = reply; self.tools.clockRead = Date()
                if abs(date.timeIntervalSinceNow) <= 120 { self.operations.verifiedChange(change.key,repeater:c.id); self.operations.clockChecked(repeater:c.id,text:reply); self.notice = "Hodiny odpovídají času Macu v toleranci odpovědi." }
                else { self.notice = "Hodiny se liší od Macu. Nebyla odeslána synchronizace ani restart." }
            case .status:
                let status = try await self.session.status(key:c.key)
                guard self.connectionGeneration == generation, self.selectedID == c.id else { throw MeshError.disconnected }
                self.acceptHealth(status,contact:c)
                self.notice = "Dostupnost ověřena. Samotná odpověď nepotvrzuje restart; zkontrolujte uptime a hodiny."
            case .manual: self.notice = "Tato operace nemá jednoznačné kontrolní čtení. Ověřte výsledek ručně v příslušném nástroji."; return
            }
            self.verified[c.id] = Date()
        }
    }
    var hardwareScope: HardwareCheck? {
        guard let account = selfInfo?.key.hex, let repeater = selectedID, let info = deviceInfo, !evidenceFirmware.isEmpty else { return nil }
        let firmware = info.version
        guard firmware.utf8.count <= 200, DiagnosticReport.version(firmware) != "Nenačteno / neuvedeno" else { return nil }
        return HardwareCheck(account:account,repeater:repeater,companionFirmware:firmware,repeaterFirmware:evidenceFirmware,appVersion:Self.appVersion,osVersion:Self.osVersion,architecture:Self.architecture,test:.pairing,outcome:.notTested)
    }
    func reportInput() -> DiagnosticReportInput {
        var input = DiagnosticReportInput()
        input.appVersion = Self.appVersion; input.osVersion = Self.osVersion; input.architecture = Self.architecture
        input.companionFirmware = deviceInfo?.version ?? ""; input.repeaterFirmware = tools.firmware ?? ""; input.protocolVersion = deviceInfo?.protocolVersion
        input.connected = ble.ready; input.authenticated = admin; input.reconnectRequired = session.requiresReconnect
        input.messages = messages.records.count; input.pendingChanges = operations.current.unverified.count
        input.events = logs.map { ReportEvent(date:$0.date,category:DiagnosticEvent.classify($0.text)) }
        if let scope = hardwareScope {
            input.checks = HardwareTest.allCases.map { test in
                let saved = library.document.checks.last{$0.sameScope(as:scope) && $0.test == test}
                return "\(test.rawValue): \((saved?.outcome ?? .notTested).rawValue)"
            }
        }
        return input
    }
    func exportReport(_ text: String) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]; panel.nameFieldStringValue = "MeshCore-report.txt"
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            do { try text.write(to:url,atomically:true,encoding:.utf8) }
            catch { self?.error = "Report se nepodařilo uložit." }
        }
    }
}
