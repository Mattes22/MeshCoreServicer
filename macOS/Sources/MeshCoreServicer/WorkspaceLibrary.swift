import Foundation
import Combine
import MeshCoreKit

struct WorkspaceDocument: Codable {
    var version = 1
    var profiles: [CompanionProfile] = []
    var shortcuts: [ConsoleShortcut] = []
    var evidence: [CommandEvidence] = []
    var checks: [HardwareCheck] = []
    func validate() throws {
        guard version == 1, profiles.count <= 32, shortcuts.count <= 128, evidence.count <= 1024, checks.count <= 256,
              Set(profiles.map(\.id)).count == profiles.count else { throw MeshError.invalid("knihovna pracovních profilů") }
        let accounts = Set(profiles.map(\.id))
        for p in profiles {
            _ = try RepeaterCommand.publicKey(p.id)
            guard p.alias.utf8.count <= 80, p.name.count <= 80, (5...1440).contains(p.options.monitorMinutes) else { throw MeshError.invalid("profil companionu") }
            _ = try DiagnosticPlan(intervalMinutes:p.options.diagnosticMinutes,samples:p.options.diagnosticSamples,route:.known)
        }
        for shortcut in shortcuts { try shortcut.validate(); guard accounts.contains(shortcut.account) else { throw MeshError.invalid("účet zkratky") } }
        for e in evidence {
            _ = try RepeaterCommand.publicKey(e.repeater)
            guard accounts.contains(e.account), e.firmware.utf8.count <= 200, ConsoleCatalog.entries.contains(where:{$0.command == e.command}) else { throw MeshError.invalid("evidence příkazů") }
        }
        for c in checks {
            _ = try RepeaterCommand.publicKey(c.repeater)
            guard accounts.contains(c.account), c.companionFirmware.utf8.count <= 200, c.repeaterFirmware.utf8.count <= 200, c.appVersion.utf8.count <= 80, c.osVersion.utf8.count <= 80, ["","arm64","x86_64"].contains(c.architecture) else { throw MeshError.invalid("záznam fyzického testu") }
        }
    }
}
@MainActor final class WorkspaceLibrary: ObservableObject {
    @Published private(set) var document = WorkspaceDocument()
    @Published private(set) var account: String?
    @Published private(set) var storageError: String?
    private let defaults: UserDefaults?
    private var writable = true
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        guard let data = defaults?.data(forKey:"workspaceLibrary") else { return }
        do {
            guard data.count <= 2_000_000 else { throw MeshError.invalid("velikost knihovny") }
            let decoded = try JSONDecoder().decode(WorkspaceDocument.self,from:data); try decoded.validate(); document = decoded
        } catch { writable = false; storageError = "Knihovnu profilů nelze načíst. Původní data nebudou přepsána." }
    }
    var profile: CompanionProfile? { document.profiles.first{$0.id == account} }
    var shortcuts: [ConsoleShortcut] { document.shortcuts.filter{$0.account == account} }
    @discardableResult func activate(account: String,name: String,bluetoothID: UUID?,defaults options: DevicePreferences) throws -> CompanionProfile {
        _ = try RepeaterCommand.publicKey(account)
        if let i = document.profiles.firstIndex(where:{$0.id == account}) {
            document.profiles[i].name = String(name.prefix(80)); document.profiles[i].lastConnected = Date()
            if let bluetoothID { document.profiles[i].bluetoothID = bluetoothID }
        } else {
            guard document.profiles.count < 32 else { throw MeshError.invalid("nejvýše 32 profilů; nejprve odstraňte nepoužívaný profil") }
            var profile = CompanionProfile(id:account,name:name,bluetoothID:bluetoothID); profile.options = options
            document.profiles.append(profile)
        }
        self.account = account; persist(); return profile!
    }
    func deactivate() { account = nil }
    func updateOptions(_ options: DevicePreferences) {
        guard let i = document.profiles.firstIndex(where:{$0.id == account}) else { return }
        document.profiles[i].options = options; persist()
    }
    func rename(_ id: String,alias: String) throws {
        let value = alias.trimmingCharacters(in:.whitespacesAndNewlines)
        guard value.utf8.count <= 80, !value.contains(where:{$0.isNewline || $0 == "\0"}) else { throw MeshError.invalid("místní název profilu, nejvýše 80 bajtů") }
        guard let i = document.profiles.firstIndex(where:{$0.id == id}) else { return }
        document.profiles[i].alias = value; persist()
    }
    func removeProfile(_ id: String) {
        guard id != account else { return }
        document.profiles.removeAll{$0.id == id}; document.shortcuts.removeAll{$0.account == id}
        document.evidence.removeAll{$0.account == id}; document.checks.removeAll{$0.account == id}; persist()
    }
    func saveShortcut(title: String,command: String,template: Bool) throws {
        guard let account else { throw MeshError.invalid("nejprve připojte companion") }
        let shortcut = try ConsoleShortcut(account:account,title:title,command:command,template:template)
        guard document.shortcuts.count < 128 else { throw MeshError.invalid("nejvýše 128 zkratek") }
        document.shortcuts.append(shortcut); persist()
    }
    func removeShortcut(_ id: UUID) { document.shortcuts.removeAll{$0.id == id && $0.account == account}; persist() }
    func record(_ evidence: CommandEvidence) {
        guard evidence.account == account else { return }
        document.evidence.removeAll { $0.command == evidence.command && $0.matches(account:evidence.account,repeater:evidence.repeater,firmware:evidence.firmware,session:evidence.session) }
        document.evidence.append(evidence); document.evidence = Array(document.evidence.suffix(1024)); persist()
    }
    func support(command: String,repeater: String,firmware: String,session: UUID) -> CommandEvidence? {
        guard let account else { return nil }
        return document.evidence.last { $0.command == command && $0.matches(account:account,repeater:repeater,firmware:firmware,session:session) }
    }
    func recordCheck(_ check: HardwareCheck) {
        guard document.profiles.contains(where:{$0.id == check.account}) else { return }
        document.checks.removeAll{$0.test == check.test && $0.sameScope(as:check)}
        if check.outcome != .notTested { document.checks.append(check) }
        document.checks = Array(document.checks.suffix(256)); persist()
    }
    private func persist() {
        guard writable, let defaults else { return }
        do { try document.validate(); defaults.set(try JSONEncoder().encode(document),forKey:"workspaceLibrary") }
        catch { storageError = "Knihovnu profilů nelze uložit. Změna zůstala pouze v paměti." }
    }
}
