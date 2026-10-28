import Foundation

/// MeshCore 1.18.0, commit 81dbae592ffad40b4212bc0b37e82b38da08f4bc.
public struct USBFrameDecoder {
    private var buffer = [UInt8]()
    public init() {}
    public static func encode(_ payload: Data) throws -> Data {
        guard (1...176).contains(payload.count) else { throw MeshError.invalid("USB rámec musí mít 1–176 bajtů, bez dělení") }
        return Data([0x3c,UInt8(payload.count),0])+payload
    }
    public mutating func feed(_ data: Data) throws -> [Data] {
        var frames = [Data]()
        for byte in data {
            buffer.append(byte)
            while buffer.count >= 3 {
                guard buffer[0] == 0x3e else { buffer.removeFirst(); continue }
                let length = Int(buffer[1]) | Int(buffer[2]) << 8
                guard (1...176).contains(length) else { throw MeshError.invalid("délka USB rámce; ověřte USB companion firmware a obnovte spojení") }
                if buffer.count < length+3 { break }
                frames.append(Data(buffer[3..<length+3])); buffer.removeFirst(length+3)
            }
        }
        return frames
    }
}
public struct USBLineDecoder {
    private var buffer = Data()
    public init() {}
    public mutating func feed(_ data: Data) throws -> [String] {
        var lines = [String]()
        for byte in data {
            if byte == 10 {
                guard let line = String(data:buffer,encoding:.utf8) else { throw MeshError.invalid("USB CLI UTF-8") }
                lines.append(line.hasSuffix("\r") ? String(line.dropLast()) : line); buffer.removeAll(keepingCapacity:true)
            } else {
                guard buffer.count < 2048 else { throw MeshError.invalid("příliš dlouhý řádek USB CLI") }
                buffer.append(byte)
            }
        }
        return lines
    }
}
@MainActor public protocol USBByteConnection: AnyObject {
    var ready: Bool { get }
    var onBytes: ((Data)->Void)? { get set }
    var onClosed: (()->Void)? { get set }
    func writeBytes(_ bytes: Data) async throws
}
@MainActor public final class USBRepeaterSession {
    private let port: USBByteConnection
    private var decoder = USBLineDecoder()
    private var pending: CheckedContinuation<String,Error>?
    private var expected: String?
    private var timer: Task<Void,Never>?
    private var counter = 0
    private var epoch = UUID()
    private let timeout: UInt64
    private let sleep: (UInt64) async throws -> Void
    public private(set) var requiresReconnect = false
    public init(port: USBByteConnection, timeout: UInt64 = 8_000_000_000, sleep: @escaping (UInt64) async throws -> Void = {try await Task.sleep(nanoseconds:$0)}) {
        self.port = port; self.timeout = timeout; self.sleep = sleep
        port.onBytes = { [weak self] in self?.receive($0) }
        port.onClosed = { [weak self] in self?.reset() }
    }
    public func reset() {
        epoch = UUID(); finish(.failure(MeshError.disconnected)); decoder = USBLineDecoder(); requiresReconnect = false
    }
    private func finish(_ result: Result<String,Error>) {
        let c = pending; pending = nil; expected = nil; timer?.cancel(); timer = nil; c?.resume(with:result)
    }
    private func receive(_ bytes: Data) {
        do {
            for line in try decoder.feed(bytes) {
                let text = line.trimmingCharacters(in:.whitespaces)
                if let tag = expected, text.hasPrefix("-> "+tag) { finish(.success(String(text.dropFirst(3+tag.count)).trimmingCharacters(in:.whitespaces))) }
            }
        } catch { requiresReconnect = true; finish(.failure(error)) }
    }
    public static func validate(_ command: String) throws {
        guard !command.isEmpty, command.utf8.count <= 154, !command.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains) else { throw MeshError.invalid("USB příkaz: jeden řádek do 154 UTF-8 bajtů, bez řídicích znaků") }
        guard !command.contains("|") || command.hasPrefix("set owner.info ") else {throw MeshError.invalid("znak | je povolen pouze uvnitř owner.info")}
        let parts = command.split(separator:" ").map(String.init)
        let sensitive = parts.count > 1 && ["get","set"].contains(parts[0]) && ["prv","private","secret","password","pin"].contains(where:parts[1].lowercased().contains)
        guard command != "erase", command != "log", command != "get acl", !command.hasPrefix("region load"), !sensitive || command.hasPrefix("password ") || command.hasPrefix("set guest.password ") else { throw MeshError.invalid("nepodporovaný USB příkaz: výpis bez párované odpovědi, citlivé klíče nebo mazání") }
    }
    public func command(_ text: String) async throws -> String {
        try Task.checkCancellation()
        try Self.validate(text)
        guard port.ready else { throw MeshError.disconnected }
        guard pending == nil else { throw MeshError.busy }
        guard !requiresReconnect else { throw MeshError.uncertain }
        guard counter < 3844 else { throw MeshError.remote("Došly jedinečné značky USB CLI; restartujte aplikaci.") }
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        let tag = String([alphabet[counter/62],alphabet[counter%62]])+"|";counter += 1
        let generation = epoch
        let noReply = ["reboot","clkreboot","poweroff","shutdown"].contains(where:text.hasPrefix)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { c in
                pending = c; expected = tag
                timer = Task { [weak self] in
                    do { try await self?.sleep(self?.timeout ?? 0) } catch { return }
                    guard self?.epoch == generation, self?.expected == tag else { return }
                    self?.requiresReconnect = true; self?.finish(.failure(MeshError.remote("USB repeater neodpověděl označenou odpovědí. Výsledek není známý; obnovte USB spojení a ověřte firmware/režim.")))
                }
                Task { [weak self] in
                    guard self?.epoch == generation, self?.expected == tag else {return}
                    do {
                        try await self?.port.writeBytes(Data((tag+text+"\r").utf8))
                        if noReply, self?.epoch == generation, self?.expected == tag { self?.requiresReconnect = true; self?.finish(.success("Odesláno po USB; restart/vypnutí nemá potvrzující odpověď. Znovu připojte zařízení.")) }
                    } catch { if self?.epoch == generation, self?.expected == tag { self?.requiresReconnect = true; self?.finish(.failure(error)) } }
                }
            }
        } onCancel: { Task { @MainActor [weak self] in if self?.epoch == generation, self?.expected == tag { self?.requiresReconnect = true; self?.finish(.failure(CancellationError())) } } }
    }
}
@MainActor public final class SwitchingMeshTransport: MeshTransport {
    private let ble: MeshTransport
    private let usb: MeshTransport
    public private(set) var isUSB = false
    public var onFrame: ((Data)->Void)?
    public var onDisconnect: (()->Void)?
    public init(ble: MeshTransport,usb: MeshTransport) {
        self.ble = ble; self.usb = usb
        ble.onFrame = { [weak self] in if self?.isUSB == false { self?.onFrame?($0) } }
        usb.onFrame = { [weak self] in if self?.isUSB == true { self?.onFrame?($0) } }
        ble.onDisconnect = { [weak self] in if self?.isUSB == false { self?.onDisconnect?() } }
        usb.onDisconnect = { [weak self] in if self?.isUSB == true { self?.onDisconnect?() } }
    }
    public func selectUSB(_ value: Bool) { guard value != isUSB else { return }; onDisconnect?(); isUSB = value }
    public func write(_ frame: Data) async throws { try await (isUSB ? usb : ble).write(frame) }
}
