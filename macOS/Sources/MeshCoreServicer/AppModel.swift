import SwiftUI
import MeshCoreKit
import UniformTypeIdentifiers
import Combine

enum LogLevel: String, CaseIterable { case info = "Události", warning = "Upozornění", error = "Chyby" }
struct LogLine: Identifiable { let id = UUID(); let date = Date(); let text: String; var level: LogLevel = .info }
enum CommandState { case waiting, replied, sentWithoutReply, failed }
struct ConsoleLine: Identifiable { let id = UUID(); let date = Date(); let target: String; let targetID: String; let command: String; var response: String; var state: CommandState = .waiting }
enum FieldState { case reading, sending, verifying, confirmed, different, unsupported, failed, uncertain }
@MainActor final class AppModel: ObservableObject {
    let ble: BluetoothTransport
    let usb: USBTransport
    let companionLink: SwitchingMeshTransport
    let usbRepeater: USBRepeaterModel
    var companionReady: (() -> Void)?
    var linkReady: Bool { companionLink.isUSB ? usb.ready && usb.mode == .companion : ble.ready }
    var directUSB: Bool { companionLink.isUSB && usb.mode == .repeater }
    var linkLabel: String { companionLink.isUSB ? "USB" : "BLE" }
    let messages: MessagesModel
    let session: MeshSession
    let operations: OperationsModel
    let preferences: AppPreferences
    let notifications: NotificationCoordinator
    let library: WorkspaceLibrary
    var applyingMeasurementOptions = false
    var initialDeviceOptions: DevicePreferences
    var requestedProfileID: String?
    var consoleAccount: String?
    var subscriptions: Set<AnyCancellable> = []
    var liveNotifications = false
    var openMainWindow: (() -> Void)?
    @Published var showMessagesRequested = false
    @Published var monitoring = false
    @Published var monitorSampleLimit = DiagnosticPlan.defaultSamples { didSet { saveProfilePreferences() } }
    @Published var measurement: DiagnosticMeasurement?
    @Published var monitorIntervalMinutes = DiagnosticPlan.defaultIntervalMinutes { didSet { saveProfilePreferences() } }
    @Published var monitorNext: Date?
    @Published var restorePreview: SnapshotComparison?
    var monitorTask: Task<Void,Never>?
    @Published var contacts: [Contact] = []
    @Published var selectedID: String? { didSet { if oldValue != selectedID { adminID = nil; config = [:]; edits = [:]; fieldStates = [:]; fieldErrors = [:]; configDates = [:]; stats = nil; statsDate = nil; password = ""; restartRequired = false; tools = RepeaterToolsState(); stopMonitoring(); restorePreview = nil; operations.select(selectedID) } } }
    @Published var tools = RepeaterToolsState()
    @Published var adminID: String? { didSet { if adminID == nil { stopMonitoring() } } }
    @Published var selfInfo: SelfInfo?
    @Published var deviceInfo: DeviceInfo?
    @Published var battery: UInt16?
    @Published var initialized = false
    let updates = AppUpdates()
    @Published var busy = false
    @Published var progress = "Připraveno"
    @Published var error: String?
    @Published var password = ""
    @Published var remember = true
    @Published var config: [String:String] = [:]
    @Published var edits: [String:String] = [:]
    @Published var stats: RepeaterStatus?
    @Published var statsDate: Date?
    @Published var verified: [String:Date] = [:]
    @Published var advertReceived: [String:Date] = [:]
    @Published var discovered: [String:String] = [:]
    @Published var logs: [LogLine] = []
    @Published var console: [ConsoleLine] = []
    @Published var history: [String] = []
    @Published var command = ""
    @Published var confirmation: Confirmation?
    @Published var fieldStates: [String:FieldState] = [:]
    @Published var fieldErrors: [String:String] = [:]
    @Published var configDates: [String:Date] = [:]
    @Published var restartRequired = false
    @Published var notice: String?
    @Published var completedSteps = 0
    @Published var totalSteps = 0
    @Published var discoveryEnds: Date?
    var connectionGeneration = UUID()
    var messageSyncTask: Task<Void,Never>?
    var syncRequested = false
    private var discoveryTag: UInt32?
    private var discoveryUntil = Date.distantPast
    var knownSecrets: Set<String> = []
    struct Confirmation: Identifiable { let id = UUID(); let title: String; let message: String; let action: () -> Void }
    var selected: Contact? { contacts.first { $0.id == selectedID } }
    var admin: Bool { adminID != nil && adminID == selectedID && initialized && !session.requiresReconnect }
    var dirtyKeys: [String] { CLIValidation.keys.filter { isDirty($0) } }
    func isDirty(_ key: String) -> Bool {
        guard let actual = config[key], let draft = edits[key] else { return false }
        return !MeshPresentation.sameValue(key:key, actual, draft)
    }
    func selectRepeater(_ id: String?, then: @escaping () -> Void = {}) {
        guard !busy else { return }
        guard selectedID != id else { then(); return }
        let action = { self.selectedID = id; then() }
        if !dirtyKeys.isEmpty {
            confirmation = Confirmation(title:"Zahodit rozepsané změny?", message:"U repeateru \(selected?.name ?? "") máte \(dirtyKeys.count) neuložených hodnot. Přepnutím uzlu se rozepsané změny zahodí.", action:action)
        } else { action() }
    }
    convenience init() { self.init(ble:BluetoothTransport(),archive:ChatArchive.applicationArchive(),operationsArchive:OperationsArchive.applicationArchive(),preferences:AppPreferences(defaults:.standard),notifications:NotificationCoordinator(systemEnabled:true),library:WorkspaceLibrary(defaults:.standard)) }
    init(traffic: ServiceTrafficGovernor? = nil, ble: BluetoothTransport, transport: MeshTransport? = nil, archive: ChatArchive? = nil, operationsArchive: OperationsArchive? = nil, preferences: AppPreferences? = nil, notifications: NotificationCoordinator? = nil, library: WorkspaceLibrary? = nil) {
        self.ble = ble
        let usb = USBTransport();self.usb = usb
        let link = SwitchingMeshTransport(ble:ble,usb:usb);self.companionLink = link
        self.operations = OperationsModel(archive:operationsArchive)
        self.preferences = preferences ?? AppPreferences()
        self.notifications = notifications ?? NotificationCoordinator()
        self.library = library ?? WorkspaceLibrary()
        self.initialDeviceOptions = self.preferences.deviceOptions
        self.messages = MessagesModel(archive:archive)
        self.session = MeshSession(traffic:traffic,transport:transport ?? link)
        self.usbRepeater = USBRepeaterModel(usb:usb,companion:self.session)
        self.preferences.onProfileChange = { [weak self] in self?.saveProfilePreferences() }
        self.preferences.$autoReconnect.sink { [weak ble] value in ble?.automaticReconnect = value }.store(in:&subscriptions)
        self.messages.$records.sink { [weak self] records in
            guard let self else { return }
            self.notifications.setUnread(records.filter{ !$0.outgoing && !$0.seen }.count)
            if let account = self.messages.account { self.notifications.removeRead(account:account,unread:Set(records.filter{ !$0.outgoing && !$0.seen }.map(\.conversationID))) }
        }.store(in:&subscriptions)
        self.notifications.onOpen = { [weak self] account,conversation in
            guard let self else { return }
            self.openMainWindow?()
            if self.messages.account == account { self.messages.select(conversation); self.showMessagesRequested = true }
            else { self.notice = "Oznámení patří jinému companionu. Připojte původní zařízení pro jeho konverzaci." }
        }
        self.messages.onIncoming = { [weak self] record in
            guard let self, let account = self.messages.account, let notice = MessageNotification.make(record,account:account,preferences:self.preferences,live:self.liveNotifications) else { return }
            self.notifications.deliver(notice,sound:self.preferences.sound)
        }
        session.onCLIReply = { [weak self] key,command,reply in self?.observeCLI(key:key,command:command,reply:reply) }
        session.onEvent = { [weak self] in self?.event($0) }
        session.onProgress = { [weak self] in self?.progress = $0 }
        session.onMalformed = { [weak self] in self?.log("Odmítnut neplatný nebo zkrácený protokolový rámec.") }
        let actualTransport = transport ?? link
        let reset = actualTransport.onDisconnect
        actualTransport.onDisconnect = { [weak self] in
            reset?(); guard let self else { return }
            self.messageSyncTask?.cancel(); self.syncRequested = false; self.messages.disconnected()
            self.tools = RepeaterToolsState(); self.liveNotifications = false; self.stopMonitoring(); self.restorePreview = nil
            self.connectionGeneration = UUID(); self.initialized = false; self.adminID = nil; self.config = [:]; self.edits = [:]; self.stats = nil
            self.contacts = []; self.verified = [:]; self.advertReceived = [:]; self.discovered = [:]
            self.library.deactivate()
            self.selfInfo = nil; self.deviceInfo = nil; self.battery = nil; self.password = ""
            self.fieldStates = [:]; self.fieldErrors = [:]; self.configDates = [:]; self.restartRequired = false; self.discoveryEnds = nil; self.confirmation = nil
            self.log("Spojení ukončeno; relace správce zrušena.")
        }
        companionReady = { [weak self] in
            guard let self else { return }
            let generation = self.connectionGeneration
            Task { [weak self] in
                while self?.busy == true && self?.connectionGeneration == generation {
                    try? await Task.sleep(nanoseconds:100_000_000)
                }
                guard let self, self.linkReady, self.connectionGeneration == generation else { return }
                self.perform("Načítám informace companionu…") {
                    do {
                    try await self.session.initialize()
                    guard self.selfInfo != nil else { throw MeshError.invalid("identitu companionu se nepodařilo ověřit") }
                    if let identity = self.selfInfo?.key { await self.messages.activate(account:identity.hex); await self.operations.activate(account:identity.hex); self.operations.select(self.selectedID) }
                    guard self.linkReady, self.connectionGeneration == generation else { throw MeshError.disconnected }
                    if let count = self.deviceInfo?.maxChannels { try await self.session.channels(count:count) }
                    guard self.linkReady, self.connectionGeneration == generation else { throw MeshError.disconnected }
                    self.initialized = true; self.requestMessageSync()
                    self.log("Načteny informace companionu. Žádná LoRa operace nebyla automaticky spuštěna.")
                    } catch {if self.companionLink.isUSB {self.usb.disconnect()};throw error}
                }
            }
        }
        ble.onReady = { [weak self] in self?.companionReady?() }
        usb.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in:&subscriptions)
        usbRepeater.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in:&subscriptions)
        usbRepeater.confirm = { [weak self] title,message,action in
            self?.confirmation = Confirmation(title:title,message:message,action:action)
        }
    }
    func disconnectAll() { stopMonitoring();usb.disconnect();ble.disconnect() }
    func connectUSB(_ path: String,mode: USBMode) {
        guard !busy, !usb.connecting, !usbRepeater.busy, !ble.connecting else { return }
        disconnectAll();companionLink.selectUSB(true);requestedProfileID = nil
        perform("Připojuji USB zařízení…") {
            do {
                try await self.usb.open(path,mode:mode)
                if mode == .companion { self.companionReady?() }
                else { try await self.usbRepeater.initialize() }
            } catch { self.usb.disconnect();throw error }
        }
    }
    func log(_ text: String, level: LogLevel = .info) { logs.append(LogLine(text:text,level:level)); if logs.count > 2000 { logs.removeFirst(logs.count-2000) } }
    func clean(_ text: String) -> String { knownSecrets.filter { !$0.isEmpty }.reduce(text) { $0.replacingOccurrences(of:$1, with:"[skryto]") } }
    func perform(_ title: String, _ action: @escaping () async throws -> Void) {
        guard !updates.installing else { error = "Probíhá instalace aktualizace; nový požadavek nebyl odeslán."; return }
        guard !busy, !usbRepeater.busy else { error = "Probíhá jiná operace. Požadavek nebyl zařazen do fronty."; return }; busy = true; progress = title; error = nil; notice = nil; completedSteps = 0; totalSteps = 0
        Task { [self] in defer { busy = false }
            let generation = connectionGeneration, target = selectedID, wasAdmin = admin
            do {
                try session.beginServiceOperation { [weak self] in
                    guard let self else { return false }
                    return self.connectionGeneration == generation && self.selectedID == target && (!wasAdmin || self.admin)
                }
                defer { session.endServiceOperation() }
                try await action(); progress = "Dokončeno"
            }
            catch { stopMonitoring(); let message = clean(error.localizedDescription); self.error = message; progress = "Operace selhala"; log("Operace selhala; podrobnosti jsou zobrazeny v aplikaci.", level:.error) }
        }
    }
    func event(_ frame: Frame) {
        switch frame {
        case .selfInfo(let s):
            guard activateProfile(s) else { return }; selfInfo = s
        case .deviceInfo(let d): deviceInfo = d
        case .login(let prefix, let permissions) where selected?.key.prefix(6) == prefix && permissions & 1 == 0: adminID = nil
        case .loginFailed(let prefix) where selected?.key.prefix(6) == prefix: adminID = nil
        case .battery(let b): battery = b
        case .contactsStart: contacts.removeAll { $0.stored }
        case .contact(let c):
            if let i = contacts.firstIndex(where: { $0.id == c.id }) { var copy = c; copy.stored = c.stored || contacts[i].stored; contacts[i] = copy } else { contacts.append(c) }
            contacts.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .advert(let key):
            advertReceived[key.hex] = Date(); log("Companion oznámil advert / aktualizaci cesty uzlu \(key.hex.prefix(12)).")
            // Refresh is a local read, delayed until the current transaction ends.
            let generation = connectionGeneration
            Task { [weak self] in
                while self?.busy == true { try? await Task.sleep(nanoseconds:300_000_000) }
                guard let self, self.initialized, self.connectionGeneration == generation else { return }
                self.perform("Aktualizuji kontakt po advertu…") { try await self.session.contact(key:key) }
            }
        case .discovery(let d):
            guard d.tag == discoveryTag, Date() < discoveryUntil else { return }
            let id = d.key.hex
            discovered[id] = String(format:"Discovery: odpověď na companionu RSSI %d dBm, SNR %.2f dB; požadavek na repeateru SNR %.2f dB", d.companionRSSI,d.companionSNR,d.repeaterSNR)
            verified[id] = Date()
            if d.key.count == 32, !contacts.contains(where: { $0.id == id }) { var c = Contact(key:d.key, kind:d.kind, name:"Objevený repeater \(id.prefix(8))"); c.outPathLength = 0; contacts.append(c) }
            log("Přijata odpověď discovery od \(id.prefix(12)).")
        case .channelInfo(let c): messages.setChannel(c)
        case .channelMessage(let m): messages.receive(m)
        case .acknowledgement(let code,let trip): messages.acknowledge(code:code,roundTrip:trip)
        case .groupObservation(let observation): messages.observe(observation)
        case .messagesWaiting: requestMessageSync()
        case .message(let m):
            messages.receive(m,contacts:contacts)
            if let snr = m.snr { log(String(format:"Přijatá zpráva od %@, čas odesílatele %u: SNR posledního LoRa příjmu na companionu %.2f dB.", String(m.prefix.hex),m.timestamp,snr)) }
        default: break
        }
    }
    func loadContacts() { perform("Načítám uložené kontakty…") { try await self.session.contacts(); self.log("Načteny kontakty companionu; uložený kontakt není důkaz dostupnosti.") } }
    func storeContact(_ c: Contact) {
        perform("Ukládám objevený kontakt do companionu…") {
            try await self.session.contacts()
            guard self.contacts.first(where: { $0.id == c.id })?.stored != true else { return }
            try await self.session.addContact(c)
            try await self.session.contact(key:c.key)
            self.log("Companion potvrdil ruční uložení nového kontaktu.")
        }
    }
    func discover() {
        guard (deviceInfo?.protocolVersion ?? 0) >= 8 else { error = "Discovery vyžaduje companion protokol v8+."; return }
        guard !busy else { return }
        let tag = UInt32.random(in:1...UInt32.max); discoveryTag = tag; discoveryUntil = Date().addingTimeInterval(30); discoveryEnds = discoveryUntil
        perform("Odesílám zero-hop discovery repeaterů…") { try await self.session.discover(tag:tag,onSend:{ self.discoveryUntil = Date().addingTimeInterval(30); self.discoveryEnds = self.discoveryUntil }); self.log("Companion přijal zero-hop discovery. Odpovědi přijímám 30 sekund; žádná odpověď neznamená neověřenou dostupnost.") }
    }
    func login() {
        guard !busy, let c = selected, c.stored else { return }
        adminID = nil
        let secret = password; knownSecrets.insert(secret); password = ""
        perform("Přihlašuji správce repeateru…") {
            let permissions = try await self.session.login(key:c.key, password:secret)
            self.verified[c.id] = Date()
            guard permissions & 1 != 0 else { throw MeshError.remote("Přihlášení neposkytlo oprávnění správce (legacy odpověď nebo přístup hosta).") }
            self.adminID = c.id
            self.operations.verifiedChange("Heslo správce · ověřte přihlášením",repeater:c.id)
            if self.remember { try KeychainStore.save(secret, key:c.id) }
            self.log("Repeater potvrdil přihlášení správce.")
        }
    }
    func loadPassword() {
        guard let c = selected else { return }
        do { password = try KeychainStore.load(c.id) ?? ""; if !password.isEmpty { knownSecrets.insert(password) } } catch { self.error = error.localizedDescription }
    }
    func forgetPassword() { guard let c = selected else { return }; do { try KeychainStore.delete(c.id); password = "" } catch { self.error = error.localizedDescription } }
    func ping() {
        guard let c = selected, c.stored else { return }
        perform("Ověřuji dostupnost žádostí o stav…") { let status = try await self.session.status(key:c.key); self.acceptHealth(status,contact:c); self.log("Repeater odpověděl na žádost o stav.") }
    }
    func readConfig(keys: [String] = CLIValidation.basicKeys + ["owner.info","dutycycle","path.hash.mode"]) {
        guard admin, let c = selected, !busy else { return }
        let action = { self.perform("Načítám konfiguraci repeateru…") {
            self.totalSteps = keys.count
            for key in keys {
                self.progress = "Načítám \(key)…"; self.fieldStates[key] = .reading; self.fieldErrors[key] = nil
                do {
                    let reply = try await self.session.cli(key:c.key, command:"get \(key)")
                    if CLIValidation.isErrorReply(reply) {
                        self.fieldStates[key] = .unsupported; self.fieldErrors[key] = self.clean(reply)
                        self.config[key] = nil; self.edits[key] = nil
                    } else {
                        let value = Self.cliValue(reply)
                        self.config[key] = value; self.edits[key] = value; self.configDates[key] = Date(); self.fieldStates[key] = .confirmed
                    }
                    self.completedSteps += 1
                } catch { self.fieldStates[key] = .failed; self.fieldErrors[key] = self.clean(error.localizedDescription); throw error }
            }
            self.verified[c.id] = Date(); self.log("Konfigurace byla načtena z CLI odpovědí repeateru.")
        } }
        if keys.contains(where:{ self.isDirty($0) }) {
            confirmation = Confirmation(title:"Načíst znovu a zahodit úpravy?", message:"Nové čtení nahradí rozepsané hodnoty v této skupině skutečnými odpověďmi repeateru.", action:action)
        } else { action() }
    }
    static func cliValue(_ reply: String) -> String {
        reply.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"^>\\s*", with:"", options:.regularExpression)
    }
    func discardEdits(keys: [String]? = nil) {
        for key in keys ?? dirtyKeys { edits[key] = config[key]; fieldStates[key] = nil; fieldErrors[key] = nil }
    }
    func save(_ key: String) { saveChanges(keys:[key]) }
    func saveChanges(keys: [String]? = nil) {
        guard admin, let c = selected, !busy else { return }
        let pending = (keys ?? dirtyKeys).filter { isDirty($0) }
        guard !pending.isEmpty else { return }
        do {
            guard !(pending.contains("dutycycle") && pending.contains("af")) else { throw MeshError.invalid("dutycycle a af mění stejnou hodnotu; ukládejte jen jednu z nich") }
            let values = try pending.map { ($0, try CLIValidation.validate(key:$0, value:edits[$0] ?? "")) }
            let action = {
                guard self.admin, self.selectedID == c.id else { return }
                self.perform("Ukládám změny repeateru…") {
                self.totalSteps = values.count
                for (key,value) in values {
                    try await self.writeSetting(key:key,value:value,contact:c)
                    self.completedSteps += 1
                }
                self.notice = self.restartRequired ? "Změny ověřeny. Uložené rádio se použije po restartu repeateru." : "Změny byly potvrzeny a ověřeny zpětným čtením."
                }
            }
            let summary = values.map { key,value in "\(key): \(self.config[key] ?? "—") → \(value)" }.joined(separator:"\n")
            if pending.contains("radio") {
                confirmation = Confirmation(title:"Uložit nové rádio repeateru?", message:summary + "\n\nNové rádio se použije po restartu. Může se přerušit LoRa spojení; companion musí mít odpovídající parametry.", action:action)
            } else if pending.count > 1 {
                confirmation = Confirmation(title:"Uložit \(pending.count) změny?", message:summary + "\n\nHodnoty se odešlou postupně a každá se ověří zpětným čtením. Při chybě se další změny zastaví.", action:action)
            } else { action() }
        } catch { self.error = error.localizedDescription }
    }
    func sendCLI(_ command: String? = nil, confirmed: Bool = false) {
        guard admin, let c = selected, !busy else { return }
        let text = (command ?? self.command).trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do { try ConsoleCatalog.validate(text) } catch { self.error = error.localizedDescription; return }
        let commandGeneration = connectionGeneration
        if !confirmed && (CLIValidation.needsRadioWarning(text) || CLIValidation.needsRestartConfirmation(text)) {
            confirmation = Confirmation(title:"Potvrdit příkaz?", message:"\(clean(text))\nMůže přerušit LoRa spojení. Restart neposílá odpověď a jeho provedení nelze z odeslání potvrdit.", action:{ guard self.selectedID == c.id, self.connectionGeneration == commandGeneration else { return }; self.sendCLI(text, confirmed:true) }); return
        }
        let sensitive = CLIValidation.sensitive(text)
        if !sensitive { history.removeAll { $0 == text }; history.insert(text,at:0); history = Array(history.prefix(50)) }
        let line = ConsoleLine(target:c.name, targetID:c.id, command:sensitive ? "[citlivý příkaz skryt]" : clean(text), response:"Čeká na odpověď…")
        console.append(line); if console.count > 500 { console.removeFirst() }
        let id = line.id
        if sensitive { self.command = "" }
        perform("Odesílám vzdálený CLI příkaz…") {
            do {
                let noReply = CLIValidation.needsRestartConfirmation(text)
                let mutation = !Self.readOnlyCLI(text)
                if mutation {
                    if let entry = ConsoleCatalog.entry(for:text), entry.command.hasPrefix("set ") {
                        let key = String(entry.command.dropFirst(4)), value = String(text.dropFirst(entry.command.count)).trimmingCharacters(in:.whitespaces)
                        self.operations.beginChange(key,repeater:c.id,expected:value)
                    } else { self.operations.beginChange(noReply ? "Restart" : "CLI · ověřte stav ručně",repeater:c.id) }
                }
                if noReply { self.operations.restartRequested(repeater:c.id) }
                let reply = try await self.session.cli(key:c.key, command:text, noReply:noReply)
                if let i = self.console.firstIndex(where: { $0.id == id }) { self.console[i].response = sensitive ? "[odpověď citlivého příkazu skryta]" : self.clean(reply); self.console[i].state = noReply ? .sentWithoutReply : (CLIValidation.isErrorReply(reply) ? .failed : .replied) }
                if !noReply { self.verified[c.id] = Date() }
                if text.hasPrefix("set radio "), reply.uppercased().hasPrefix("OK") {
                    self.restartRequired = true; self.operations.beginChange("Rádio · vyžaduje restart",repeater:c.id)
                }
                if noReply { self.tools.clockRead = nil; self.tools.clockResult = "Po možném restartu znovu ověřte hodiny repeateru. Provedení restartu zatím není potvrzené." }
                self.log(noReply ? "CLI požadavek bez odpovědi přijal companion; provedení neověřeno." : "Přijata CLI odpověď repeateru; obsah se do diagnostického logu neukládá.")
            } catch {
                if let i = self.console.firstIndex(where: { $0.id == id }) { self.console[i].response = self.clean(error.localizedDescription); self.console[i].state = .failed }; throw error
            }
        }
    }
    func exportLog() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]; panel.nameFieldStringValue = "MeshCore-diagnostika.txt"
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url, let self else { return }
            let formatter = ISO8601DateFormatter()
            let text = self.logs.map { "\(formatter.string(from:$0.date)) [\($0.level.rawValue)] \($0.text)" }.joined(separator:"\n")
            do { try self.clean(text).write(to:url, atomically:true, encoding:.utf8) } catch { self.error = "Export logu selhal: \(error.localizedDescription)" }
        }
    }
}
