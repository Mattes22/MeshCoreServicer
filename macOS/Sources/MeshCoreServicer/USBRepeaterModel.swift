import Foundation
import Combine
import MeshCoreKit

@MainActor final class USBRepeaterModel: ObservableObject {
    let usb: USBTransport
    let session: USBRepeaterSession
    let companion: MeshSession
    @Published var busy = false
    @Published var firmware = ""
    @Published var board = ""
    @Published var name = "USB repeater"
    @Published var progress = "USB repeater odpojen"
    @Published var error: String?
    @Published var values: [String:String] = [:]
    @Published var transcript: [String] = []
    private var task: Task<Void,Never>?
    private var generation = UUID()
    private var operationGeneration: UUID?
    var confirm: ((String,String, @escaping () -> Void)->Void)?
    var ready: Bool { usb.ready && usb.mode == .repeater && !session.requiresReconnect }
    init(usb: USBTransport,companion: MeshSession) {
        self.usb = usb; self.companion = companion;session = USBRepeaterSession(port:usb)
        let old = usb.onClosed
        usb.onClosed = { [weak self] in old?(); self?.generation = UUID();self?.task?.cancel(); self?.values = [:];self?.firmware = "";self?.board = "";self?.name = "USB repeater";self?.progress = "USB odpojeno" }
    }
    func initialize() async throws {
        guard !busy else {throw MeshError.busy};busy = true;defer {busy = false}
        error = nil;operationGeneration = generation;values = [:];transcript = [];session.reset()
        firmware = try await read("ver");board = try await read("board");name = value(try await read("get name"))
        progress = "Přímé USB CLI připraveno"
    }
    private func value(_ reply: String) -> String { let text = reply.trimmingCharacters(in:.whitespacesAndNewlines);return text.hasPrefix(">") ? String(text.dropFirst()).trimmingCharacters(in:.whitespaces) : text }
    private func read(_ command: String) async throws -> String {
        guard operationGeneration == generation else {throw MeshError.disconnected}
        try Task.checkCancellation()
        let reply = try await session.command(command)
        guard !CLIValidation.isErrorReply(reply) else { throw MeshError.remote("USB firmware odmítl příkaz: "+(CLIValidation.sensitive(command) ? "[citlivý příkaz]" : reply)) }
        return reply
    }
    func run(_ action: @escaping () async throws -> Void) {
        guard !busy, ready else {error = "Probíhá USB operace nebo je nutné obnovit USB spojení.";return}
        busy = true;error = nil;progress = "Čekám na USB odpověď…"
        operationGeneration = generation
        let epoch = generation
        task = Task { [self] in
            defer {busy = false}
            do {try await action();progress = usb.ready ? "USB odpověď přijata" : "USB požadavek odeslán; provedení restartu není potvrzené"}
            catch {if epoch == generation {self.error = error.localizedDescription;progress = "USB operace selhala"}}
        }
    }
    func readSetting(_ key: String) {run {self.values[key] = self.value(try await self.read("get "+key))}}
    func apply(_ key: String,_ input: String) {
        do {
            let value = try CLIValidation.validate(key:key,value:input)
            confirm?("Zapsat nastavení přes USB?","set \(key) \(value). Změna se ověří zpětným čtením."+(key == "radio" ? " Změna může odpojit uzel od LoRa sítě a vyžadovat restart." : "")) { [self] in
                run {
                    _ = try await self.read("set \(key) \(value)")
                    let actual = self.value(try await self.read("get "+key));self.values[key] = actual
                    guard MeshPresentation.sameValue(key:key,actual,value) else {throw MeshError.remote("Zápis byl odeslán, zpětné čtení ale změnu nepotvrdilo.")}
                }
            }
        } catch {self.error = error.localizedDescription}
    }
    func command(_ input: String) {
        let command = input.trimmingCharacters(in:.whitespacesAndNewlines)
        do {try USBRepeaterSession.validate(command)} catch {self.error = error.localizedDescription;return}
        let radio = command.hasPrefix("advert") || command.hasPrefix("discover.neighbors")
        let readOnly = !CLIValidation.sensitive(command) && (command.hasPrefix("get ") || ["ver","board","clock","neighbors","stats-core","stats-radio","stats-packets"].contains(command))
        let action = { [self] in run {
            if radio {try await self.companion.reserveDirectRadio();guard self.ready else {throw MeshError.disconnected}}
            let reply = try await self.read(command)
            self.transcript.append(Date().formatted(date:.omitted,time:.standard)+"  "+(CLIValidation.sensitive(command) ? "[citlivý příkaz a odpověď skryty]" : command+"\n"+reply))
            self.transcript = Array(self.transcript.suffix(200))
            if ["reboot","clkreboot","poweroff","shutdown"].contains(where:command.hasPrefix) {self.usb.disconnect()}
        } }
        if readOnly {action()} else {
            confirm?("Provést USB příkaz?",(CLIValidation.sensitive(command) ? "Citlivý příkaz nebude uložen do historie." : command)+(radio ? "\nTento příkaz aktivně vysílá přes sdílenou LoRa síť." : "\nPříkaz může změnit místní zařízení.")+(CLIValidation.needsRadioWarning(command) ? "\nZměna rádia může přerušit spojení se sítí." : ""),action)
        }
    }
}
