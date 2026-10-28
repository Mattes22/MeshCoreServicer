import Foundation

/// Public report content is built from an allowlist. Raw log, CLI and identity text is never copied.
public enum DiagnosticEvent: String, Sendable {
    case connected = "Načteny informace companionu", disconnected = "Relace ukončena", failure = "Operace selhala", malformed = "Odmítnut neplatný rámec", advert = "Přijat advert nebo změna cesty", discovery = "Discovery provoz", message = "Přijata LoRa zpráva", login = "Potvrzeno přihlášení", configuration = "Čtení nebo ověření konfigurace", cli = "CLI požadavek nebo odpověď", monitoring = "Změna stavu monitoringu", other = "Událost aplikace · podrobnosti vynechány"
    public static func classify(_ text: String) -> Self {
        if text.hasPrefix("Načteny informace companionu") { return .connected }
        if text.hasPrefix("BLE spojení ukončeno") || text.hasPrefix("Spojení ukončeno") { return .disconnected }
        if text.hasPrefix("Operace selhala") { return .failure }
        if text.hasPrefix("Odmítnut neplatný") { return .malformed }
        if text.hasPrefix("Companion oznámil advert") { return .advert }
        if text.hasPrefix("Přijata odpověď discovery") || text.hasPrefix("Companion přijal zero-hop discovery") { return .discovery }
        if text.hasPrefix("Přijatá zpráva od") { return .message }
        if text.hasPrefix("Repeater potvrdil přihlášení") { return .login }
        if text.hasPrefix("Konfigurace byla načtena") || text.hasPrefix("Změna ") { return .configuration }
        if text.hasPrefix("Přijata CLI odpověď") || text.hasPrefix("CLI požadavek") { return .cli }
        if text.hasPrefix("Monitoring zastaven") { return .monitoring }
        return .other
    }
}
public struct ReportEvent: Sendable {
    public let date: Date
    public let category: DiagnosticEvent
    public init(date: Date,category: DiagnosticEvent) { self.date = date; self.category = category }
}
public enum ConnectionReportKind: String, Sendable {case ble = "BLE companion", usbCompanion = "USB companion", usbRepeater = "USB repeater"}
public struct DiagnosticReportInput: Sendable {
    public var transport: ConnectionReportKind = .ble
    public var usbEvents: [USBDiagnosticEvent] = []
    public var appVersion: String = ""
    public var osVersion: String = ""
    public var architecture: String = ""
    public var companionFirmware: String = ""
    public var repeaterFirmware: String = ""
    public var protocolVersion: UInt8?
    public var connected = false
    public var authenticated = false
    public var reconnectRequired = false
    public var messages = 0
    public var pendingChanges = 0
    public var events: [ReportEvent] = []
    public var checks: [String] = []
    public init() {}
}
public enum DiagnosticReport {
    public static func version(_ text: String) -> String {
        let pattern = #"(?<![A-Za-z0-9])v?([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})(?:-([a-fA-F0-9]{7,40}))?(?![A-Za-z0-9])"#
        guard let range = text.range(of:pattern,options:.regularExpression) else { return "Nenačteno / neuvedeno" }
        let value = String(text[range])
        if range.upperBound < text.endIndex, ["-","+"].contains(text[range.upperBound]) { return value + " (doplněk sestavení vynechán)" }
        return value
    }
    public static func render(_ input: DiagnosticReportInput,includeEvents: Bool = true,date: Date = Date()) -> String {
        let iso = ISO8601DateFormatter()
        let architecture = ["arm64","x86_64"].contains(input.architecture) ? input.architecture : "Neuvedeno"
        var lines = ["MeshCore Servicer · diagnostický report", "Vytvořeno: \(iso.string(from:date))", "Aplikace: \(version(input.appVersion))", "macOS: \(version(input.osVersion))", "Architektura procesu: \(architecture)", "Referenční firmware: \(ConsoleCatalog.firmwareCommit)", "Companion firmware: \(version(input.companionFirmware))", "Repeater firmware: \(version(input.repeaterFirmware))", "Companion protokol: \(input.protocolVersion.map{String($0)} ?? "Nenačteno")", "Transport: \(input.transport.rawValue)", "Připojeno: \(input.connected ? "ano" : "ne")", "Správce přihlášen: \(input.authenticated ? "ano" : "ne")", "Nutné obnovení relace po timeoutu: \(input.reconnectRequired ? "ano" : "ne")", "Počet místních zpráv: \(max(0,input.messages))", "Neověřené změny vybraného uzlu: \(max(0,input.pendingChanges))", "", "Fyzická kompatibilita: uživatelské záznamy, nejde o automatické ověření."]
        // Accept only strings generated from the finite checklist enums.
        let allowed = Set(HardwareTest.allCases.flatMap { test in HardwareOutcome.allCases.map { "\(test.rawValue): \($0.rawValue)" } })
        let checks = input.checks.filter{allowed.contains($0)}
        lines += checks.isEmpty ? ["Žádný fyzický test není doložen."] : checks
        if includeEvents {
            lines += ["", "Průběh relace · kategorie bez původního textu:"]
            lines += input.events.suffix(500).map { "\(iso.string(from:$0.date)) \($0.category.rawValue)" }
        }
        lines += ["", "USB události · bez názvů portů a obsahu:"]
        lines += input.usbEvents.suffix(200).map { "\(iso.string(from:$0.date)) \($0.kind.rawValue)" }
        lines += ["", "Vynecháno: názvy zařízení, veřejné i privátní klíče, BLE identifikátory, hesla, souřadnice, rádio, kontakty, kanály, text zpráv, příkazů a odpovědí, původní text logu a cesty k souborům."]
        return lines.joined(separator:"\n")
    }
}
