import Foundation
import Combine
import Darwin

public enum USBMode: String, CaseIterable { case companion = "USB companion", repeater = "USB repeater (přímé CLI)" }

public enum USBEventKind: String,Sendable {case opening,opened,closed,openFailed,readFailed,invalidFrame,writeFailed}
public struct USBDiagnosticEvent: Sendable {
    public let date: Date
    public let kind: USBEventKind
    public init(date: Date = Date(),kind: USBEventKind) {self.date = date;self.kind = kind}
}
/// Native termios/Dispatch serial transport. No Web Serial, flashing or reset pulse.
@MainActor public final class USBTransport: ObservableObject, MeshTransport, USBByteConnection {
    @Published public private(set) var ready = false
    @Published public private(set) var connecting = false
    @Published public private(set) var mode: USBMode = .companion
    @Published public private(set) var state = "USB odpojeno"
    @Published public private(set) var ports: [String] = []
    public private(set) var diagnostics: [USBDiagnosticEvent] = []
    private func record(_ kind: USBEventKind) {diagnostics.append(USBDiagnosticEvent(kind:kind));diagnostics = Array(diagnostics.suffix(200))}
    public var onFrame: ((Data)->Void)?
    public var onDisconnect: (()->Void)?
    public var onBytes: ((Data)->Void)?
    public var onClosed: (()->Void)?
    private let queue = DispatchQueue(label:"MeshCoreServicer.usb.io")
    private var source: DispatchSourceRead?
    private var descriptor: Int32 = -1
    private var generation = UUID()
    private var frames = USBFrameDecoder()
    public init() {}
    public func refreshPorts() {
        ports = ((try? FileManager.default.contentsOfDirectory(atPath:"/dev")) ?? []).filter { $0.hasPrefix("cu.") && !$0.contains("Bluetooth") }.sorted().map { "/dev/"+$0 }
    }
    public func open(_ path: String,mode: USBMode) async throws {
        guard !connecting else { throw MeshError.busy }
        disconnect(); connecting = true; self.mode = mode; state = "Otevírám USB port…";record(.opening)
        let epoch = generation
        defer { connecting = false }
        do {
            let fd: Int32 = try await withCheckedThrowingContinuation { c in
                queue.async {
                    guard path.hasPrefix("/dev/"), !path.utf8.contains(0) else { c.resume(throwing:MeshError.invalid("sériový port")); return }
                    let fd = Darwin.open(path,O_RDWR|O_NOCTTY|O_NONBLOCK)
                    guard fd >= 0 else { c.resume(throwing:Self.failure("USB-OPEN",errno)); return }
                    var info = stat(), settings = termios()
                    guard fstat(fd,&info) == 0, info.st_mode & S_IFMT == S_IFCHR, ioctl(fd,TIOCEXCL) == 0, tcgetattr(fd,&settings) == 0 else { let code = errno;Darwin.close(fd);c.resume(throwing:Self.failure("USB-PORT",code));return }
                    cfmakeraw(&settings); cfsetspeed(&settings,speed_t(B115200))
                    settings.c_cflag |= tcflag_t(CLOCAL|CREAD|CS8); settings.c_cflag &= ~tcflag_t(CSTOPB|PARENB|CRTSCTS|HUPCL)
                    // cfmakeraw sets VMIN=1, VTIME=0 on Darwin. Nonblocking read drains only available bytes.
                    guard tcsetattr(fd,TCSANOW,&settings) == 0 else {let code = errno;Darwin.close(fd);c.resume(throwing:Self.failure("USB-SETUP",code));return}
                    _ = tcflush(fd,TCIFLUSH)
                    var dtr = Int32(TIOCM_DTR); _ = ioctl(fd,TIOCMBIS,&dtr)
                    c.resume(returning:fd)
                }
            }
            guard epoch == generation, !Task.isCancelled else {queue.async {Darwin.close(fd)};throw CancellationError()}
            descriptor = fd;ready = true;record(.opened);state = mode == .companion ? "USB companion · 115200 8N1" : "USB repeater · přímé místní CLI · 115200 8N1"
            let reader = DispatchSource.makeReadSource(fileDescriptor:fd,queue:queue)
            reader.setCancelHandler { Darwin.close(fd) }
            reader.setEventHandler { [weak self] in
                var storage = [UInt8](repeating:0,count:1024)
                for _ in 0..<32 {
                    let count = Darwin.read(fd,&storage,storage.count)
                    if count < 0 && (errno == EAGAIN || errno == EINTR) { return }
                    if count <= 0 { DispatchQueue.main.async { [weak self] in if self?.generation == epoch { self?.record(.readFailed);self?.disconnect();self?.state = "USB-READ: zařízení odpojeno nebo chyba čtení." } }; return }
                    let data = Data(storage.prefix(count))
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.generation == epoch, self.ready else { return }
                        do {if self.mode == .companion {for frame in try self.frames.feed(data) {self.onFrame?(frame)}}else{self.onBytes?(data)}}
                        catch {self.record(.invalidFrame);self.disconnect();self.state = "USB-FRAME: neplatný rámec; ověřte režim firmwaru a obnovte spojení."}
                    }
                }
            }
            source = reader;reader.resume()
        } catch {if epoch == generation {record(.openFailed);disconnect();state = error.localizedDescription};throw error}
    }
    nonisolated private static func failure(_ phase: String,_ code: Int32) -> MeshError {
        .remote(phase+": "+([EACCES,EPERM,EBUSY].contains(code) ? "Port není přístupný nebo jej používá jiná aplikace. Zavřete sériový monitor a ověřte oprávnění." : "USB operace selhala. Ověřte datový kabel, vybraný port a firmware.")+" (errno \(code))")
    }
    public func write(_ frame: Data) async throws {
        guard mode == .companion else { throw MeshError.invalid("binární příkaz nelze odeslat do USB CLI repeateru") }
        try await writeBytes(USBFrameDecoder.encode(frame))
    }
    public func writeBytes(_ bytes: Data) async throws {
        guard ready, descriptor >= 0 else { throw MeshError.disconnected }
        let fd = descriptor, epoch = generation
        do {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void,Error>) in
                queue.async {
                    let deadline = DispatchTime.now().uptimeNanoseconds+3_000_000_000
                    do {
                        try bytes.withUnsafeBytes { raw in
                            var offset = 0
                            while offset < raw.count {
                                guard DispatchTime.now().uptimeNanoseconds < deadline else { throw MeshError.timeout }
                                let count = Darwin.write(fd,raw.baseAddress!.advanced(by:offset),raw.count-offset)
                                if count > 0 {offset += count;continue}
                                if count < 0 && (errno == EAGAIN || errno == EINTR) {var item = pollfd(fd:fd,events:Int16(POLLOUT),revents:0);_ = poll(&item,1,50);continue}
                                throw Self.failure("USB-WRITE",errno)
                            }
                        }
                        c.resume()
                    } catch {c.resume(throwing:error)}
                }
            }
            guard epoch == generation else { throw MeshError.disconnected }
        } catch {if epoch == generation {record(.writeFailed);disconnect();state = "USB-WRITE: zápis se nezdařil; výsledek není známý."};throw error}
    }
    public func disconnect() {
        let wasOpen = ready || connecting || descriptor >= 0
        generation = UUID();ready = false;descriptor = -1;frames = USBFrameDecoder();source?.cancel();source = nil;state = "USB odpojeno"
        if wasOpen {record(.closed);onClosed?();onDisconnect?()}
    }
}
