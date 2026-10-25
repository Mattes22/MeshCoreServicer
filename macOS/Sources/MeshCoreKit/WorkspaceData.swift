import Foundation

public struct DevicePreferences: Codable, Equatable, Sendable {
    public var autoReconnect = true
    public var suggestions = true
    public var help = true
    public var history = true
    public var changes = false
    public var enterSends = true
    public var monitorMinutes = 15 // Legacy preference; never used to start or schedule diagnostics.
    public var diagnosticMinutes = 30
    public var diagnosticSamples = 3
    public init() {}
    enum CodingKeys: String, CodingKey { case autoReconnect, suggestions, help, history, changes, enterSends, monitorMinutes, diagnosticMinutes, diagnosticSamples }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        autoReconnect = try c.decodeIfPresent(Bool.self,forKey:.autoReconnect) ?? true
        suggestions = try c.decodeIfPresent(Bool.self,forKey:.suggestions) ?? true
        help = try c.decodeIfPresent(Bool.self,forKey:.help) ?? true
        history = try c.decodeIfPresent(Bool.self,forKey:.history) ?? true
        changes = try c.decodeIfPresent(Bool.self,forKey:.changes) ?? false
        enterSends = try c.decodeIfPresent(Bool.self,forKey:.enterSends) ?? true
        monitorMinutes = try c.decodeIfPresent(Int.self,forKey:.monitorMinutes) ?? 15
        diagnosticMinutes = try c.decodeIfPresent(Int.self,forKey:.diagnosticMinutes) ?? 30
        diagnosticSamples = try c.decodeIfPresent(Int.self,forKey:.diagnosticSamples) ?? 3
    }
}
public struct CompanionProfile: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var alias: String = ""
    public var bluetoothID: UUID?
    public var lastConnected: Date
    public var options = DevicePreferences()
    public var displayName: String { alias.isEmpty ? name : alias }
    public init(id: String,name: String,bluetoothID: UUID? = nil,date: Date = Date()) {
        self.id = id; self.name = String(name.prefix(80)); self.bluetoothID = bluetoothID; lastConnected = date
    }
}
public struct ConsoleShortcut: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let account: String
    public let title: String
    public let command: String
    public let template: Bool
    public init(account: String,title: String,command: String,template: Bool) throws {
        id = UUID(); self.account = account; self.title = title.trimmingCharacters(in:.whitespacesAndNewlines); self.command = command; self.template = template
        try validate()
    }
    public func validate() throws {
        _ = try RepeaterCommand.publicKey(account)
        guard !title.isEmpty, title.utf8.count <= 80, !title.contains(where:{$0.isNewline || $0 == "\0"}),
              ConsoleCatalog.entries.contains(where:{$0.command == command}), !CLIValidation.sensitive(command) else { throw MeshError.invalid("zkratka musí mít název a příkaz z katalogu bez vlastních argumentů") }
    }
    public func filled(with argument: String) throws -> String {
        try validate()
        let entry = ConsoleCatalog.entry(for:command)!
        let result = command + (entry.arguments.isEmpty ? "" : " " + argument.trimmingCharacters(in:.whitespaces))
        try ConsoleCatalog.validate(result); return result
    }
}
public enum CommandSupport: String, Codable, Sendable { case answered, unsupported, rejected }
public struct CommandEvidence: Codable, Equatable, Sendable {
    public let account: String
    public let repeater: String
    public let firmware: String
    public let session: UUID
    public let command: String
    public let result: CommandSupport
    public let date: Date
    public init(account: String,repeater: String,firmware: String,session: UUID,command: String,reply: String,date: Date = Date()) {
        self.account = account; self.repeater = repeater; self.firmware = firmware; self.session = session; self.command = command; self.date = date
        let text = reply.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        if text.hasPrefix(">") { result = .answered }
        else if text.hasPrefix("unknown command") || text.hasPrefix("not supported") || (text.hasPrefix("err") && (text.contains("not supported") || text.contains("unsupported"))) { result = .unsupported }
        else if CLIValidation.isErrorReply(reply) { result = .rejected }
        else { result = .answered }
    }
    public func matches(account: String,repeater: String,firmware: String,session: UUID) -> Bool {
        self.account == account && self.repeater == repeater && self.firmware == firmware && (!firmware.isEmpty || self.session == session)
    }
}
public enum HardwareTest: String, Codable, CaseIterable, Identifiable, Sendable {
    case pairing = "BLE připojení a párování", reconnect = "Výpadek a obnovení spojení", messages = "Zprávy a ACK", login = "Přihlášení správce", settings = "Zápis se zpětným čtením", reboot = "Restart a následná kontrola", notifications = "Systémová oznámení", sleep = "Spánek a probuzení Macu"
    public var id: String { rawValue }
}
public enum HardwareOutcome: String, Codable, CaseIterable, Sendable { case notTested = "Neprovedeno", passed = "Prošlo", failed = "Selhalo" }
public struct HardwareCheck: Codable, Equatable, Sendable {
    public let account: String
    public let repeater: String
    public let companionFirmware: String
    public let repeaterFirmware: String
    public let appVersion: String
    public let osVersion: String
    public let architecture: String
    public let test: HardwareTest
    public let outcome: HardwareOutcome
    public let date: Date
    public init(account: String,repeater: String,companionFirmware: String,repeaterFirmware: String,appVersion: String,osVersion: String = "",architecture: String = "",test: HardwareTest,outcome: HardwareOutcome,date: Date = Date()) {
        self.account = account; self.repeater = repeater; self.companionFirmware = companionFirmware; self.repeaterFirmware = repeaterFirmware; self.appVersion = appVersion; self.osVersion = osVersion; self.architecture = architecture; self.test = test; self.outcome = outcome; self.date = date
    }
    public func sameScope(as other: Self) -> Bool {
        account == other.account && repeater == other.repeater && companionFirmware == other.companionFirmware && repeaterFirmware == other.repeaterFirmware && appVersion == other.appVersion && osVersion == other.osVersion && architecture == other.architecture
    }
}
public enum VerificationAction: Equatable, Sendable {
    case setting(String), clock, status, radio, manual
    public init(key: String) {
        if CLIValidation.keys.contains(key) { self = .setting(key) }
        else if key == "Hodiny" { self = .clock }
        else if key == "Restart" { self = .status }
        else if key == "Rádio · vyžaduje restart" { self = .radio }
        else { self = .manual }
    }
    public var title: String {
        switch self { case .setting(let key): return "Načíst get \(key)"; case .clock: return "Ověřit hodiny"; case .status:return "Ověřit dostupnost"; case .radio:return "Načíst uložené rádio"; case .manual:return "Vyžaduje ruční kontrolu" }
    }
}
