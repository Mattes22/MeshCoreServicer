import Foundation

@MainActor public protocol MeshTransport: AnyObject {
    var onFrame: ((Data) -> Void)? { get set }
    var onDisconnect: (() -> Void)? { get set }
    func write(_ frame: Data) async throws
}

/// No request IDs exist for local replies or remote CLI. One whole operation at a time.
@MainActor public final class MeshSession {
    private let transport: MeshTransport
    private let traffic: ServiceTrafficGovernor
    private var routes: [Data:ServiceRoute] = [:]
    private var serviceSending = false
    public var onEvent: ((Frame) -> Void)?
    public var onProgress: ((String) -> Void)?
    public var onMalformed: (() -> Void)?
    public var onCLIReply: ((Data,String,String) -> Void)?
    public var requiresReconnect: Bool { poisoned }
    private var pending: CheckedContinuation<Frame, Error>?
    private var requestToken = UUID()
    private var expected: ((Frame) -> Bool)?
    private var timer: Task<Void, Never>?
    private var remote: [Frame] = []
    private var seen: Set<String> = []
    private var occupied = false
    private var poisoned = false
    private var generation = UUID()
    private let localTimeout: Double
    public init(traffic: ServiceTrafficGovernor? = nil, transport: MeshTransport, localTimeout: Double = 8) {
        self.traffic = traffic ?? ServiceTrafficGovernor()
        self.localTimeout = localTimeout
        self.transport = transport
        transport.onFrame = { [weak self] in self?.receive($0) }
        transport.onDisconnect = { [weak self] in self?.reset() }
    }
    public func reset() {
        routes.removeAll(); generation = UUID(); requestToken = UUID(); finish(.failure(MeshError.disconnected)); remote.removeAll(); seen.removeAll(); poisoned = false
    }
    public func route(for key: Data) -> ServiceRoute { routes[key] ?? .floodOrUnknown }
    public func beginServiceOperation(valid: @escaping () -> Bool) throws { try traffic.begin(valid:valid) }
    public func endServiceOperation() { traffic.end() }
    private func serviceRoute(_ data: Data) -> ServiceRoute? {
        let bytes = [UInt8](data)
        guard let code = bytes.first else { return nil }
        if code == 55 { return .floodOrUnknown }
        if [26,27,50].contains(code) { return routes[Data(bytes.dropFirst().prefix(32))] ?? .floodOrUnknown }
        if code == 2, bytes.count >= 13, bytes[1] == 1 {
            let command = String(decoding:bytes.dropFirst(13),as:UTF8.self)
            if ["advert","advert.zerohop"].contains(command) { return .floodOrUnknown }
            let matches = routes.filter { $0.key.prefix(6) == Data(bytes[7..<13]) }
            return matches.count == 1 ? matches.first!.value : .floodOrUnknown
        }
        return nil
    }
    private func receive(_ data: Data) {
        do {
            let frame = try MeshCodec.decode(data)
            let identity: String?
            switch frame { case .message(let m): identity = m.identity; case .channelMessage(let m): identity = m.identity; default: identity = nil }
            if let identity {
                guard seen.insert(identity).inserted else {
                    if expected?(frame) == true { finish(.success(frame)) }
                    return
                }
                if seen.count > 4096 { seen = [identity] }
            }
            switch frame {
            case .contactsStart: routes.removeAll()
            case .contact(let c): routes[c.key] = ServiceRoute.classify(path:c.outPathLength,bytes:c.outPath.count)
            case .advert(let key): routes[key] = nil
            case .sent(let receipt) where receipt.flood && serviceSending: traffic.confirmFlood(); routes.removeAll()
            default: break
            }
            onEvent?(frame)
            switch frame {
            case .login, .loginFailed, .status, .message, .binary: remote.append(frame); if remote.count > 256 { remote.removeFirst() }
            default: break
            }
            if case .error(let code) = frame, pending != nil {
                finish(.failure(MeshError.remote("Companion odmítl požadavek (kód \(code)).")))
            } else if expected?(frame) == true { finish(.success(frame)) }
        } catch { onMalformed?() }
    }
    private func finish(_ result: Result<Frame, Error>) {
        let c = pending; pending = nil; expected = nil; timer?.cancel(); timer = nil; c?.resume(with: result)
    }
    private func exchange(_ data: Data, timeout: Double? = nil, rebuild: (() throws -> Data)? = nil, prepare: (() async throws -> Void)? = nil, matching: @escaping (Frame) -> Bool) async throws -> Frame {
        guard pending == nil else { throw MeshError.busy }
        let admittedRoute = serviceRoute(data)
        if let route = admittedRoute {
            let epoch = generation
            try await traffic.acquire(route:route,progress:onProgress)
            guard epoch == generation else { throw MeshError.disconnected }
            guard serviceRoute(data) == route else { throw MeshError.remote("Trasa se během čekání změnila; požadavek se neposlal. Ověřte kontakt ručně.") }
        }
        let epoch = generation
        try await prepare?()
        guard epoch == generation else { throw MeshError.disconnected }
        if let admittedRoute {
            guard serviceRoute(data) == admittedRoute else { throw MeshError.remote("Trasa se během přípravy změnila; požadavek se neposlal.") }
            try traffic.validateContext(); remote.removeAll()
        }
        let outbound = try rebuild?() ?? data
        serviceSending = serviceRoute(data) != nil
        defer { serviceSending = false }
        let duration = timeout ?? localTimeout
        let token = UUID()
        requestToken = token
        var writing: Task<Void, Error>?
        let result: Frame = try await withCheckedThrowingContinuation { c in
            pending = c; expected = matching
            timer = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: UInt64(duration*1e9)) } catch { return }
                guard self?.requestToken == token else { return }
                self?.poisoned = true; self?.finish(.failure(MeshError.timeout))
            }
            writing = Task { [weak self] in
                do { try await self?.transport.write(outbound) }
                catch { if self?.requestToken == token { self?.poisoned = true; self?.finish(.failure(error)) }; throw error }
            }
        }
        try await writing?.value
        return result
    }
    private func operation<T>(_ body: () async throws -> T) async throws -> T {
        guard !occupied else { throw MeshError.busy }; guard !poisoned else { throw MeshError.uncertain }
        occupied = true; defer { occupied = false }; return try await body()
    }
    public func initialize() async throws {
        try await operation {
            _ = try await exchange(Data([22,3])) { if case .deviceInfo = $0 { return true }; return false }
            _ = try await exchange(MeshCodec.appStart()) { if case .selfInfo = $0 { return true }; return false }
            _ = try await exchange(Data([20])) { if case .battery = $0 { return true }; return false }
        }
    }
    public func contacts() async throws {
        try await operation { _ = try await exchange(Data([4]), timeout:45) { $0 == .contactsEnd } }
    }
    public func contact(key: Data) async throws {
        try await operation { _ = try await exchange(Data([30])+key) { if case .contact(let c) = $0 { return c.key == key }; return false } }
    }
    public func addContact(_ c: Contact) async throws {
        try await operation { _ = try await exchange(MeshCodec.addContact(c)) { $0 == .ok } }
    }
    public func discover(tag: UInt32, onSend: (() -> Void)? = nil) async throws {
        try await operation { _ = try await exchange(MeshCodec.discover(tag:tag),rebuild:{ onSend?(); return MeshCodec.discover(tag:tag) }) { $0 == .ok } }
    }
    public func channels(count: UInt8) async throws {
        try await operation {
            for index in 0..<count {
                _ = try await exchange(Data([31,index])) { if case .channelInfo(let c) = $0 { return c.index == index }; return false }
            }
        }
    }
    public func syncMessages() async throws { try await operation { try await drain() } }
    public func sendDirect(key: Data, text: String, timestamp: UInt32) async throws -> SendReceipt {
        try await operation {
            let f = try await exchange(MeshMessaging.direct(key:key,text:text,timestamp:timestamp)) { if case .sent = $0 { return true }; return false }
            guard case .sent(let receipt) = f else { throw MeshError.invalid("potvrzení zprávy") }; return receipt
        }
    }
    public func sendChannel(index: UInt8, text: String, sender: String, timestamp: UInt32) async throws {
        try await operation { _ = try await exchange(MeshMessaging.channel(index:index,text:text,sender:sender,timestamp:timestamp)) { $0 == .ok } }
    }
    private func drain() async throws {
        for _ in 0..<128 {
            let f = try await exchange(Data([10])) { switch $0 { case .message, .channelMessage, .noMessages, .other(27): return true; default:return false } }
            if f == .noMessages { return }
        }
        throw MeshError.remote("Příliš mnoho čekajících zpráv; zkuste načíst znovu.")
    }
    private func waitRemote(timeout: Double, poll: Bool = false, matching: (Frame) -> Bool) async throws -> Frame {
        let end = Date().addingTimeInterval(timeout), epoch = generation
        while Date() < end {
            guard epoch == generation else { throw MeshError.disconnected }
            if let i = remote.firstIndex(where: matching) { return remote.remove(at:i) }
            if poll { try await drain() }
            if let i = remote.firstIndex(where: matching) { return remote.remove(at:i) }
            try await Task.sleep(nanoseconds:500_000_000)
        }
        poisoned = true; throw MeshError.timeout
    }
    private func send(_ d: Data, rebuild: (() throws -> Data)? = nil, prepare: (() async throws -> Void)? = nil) async throws -> Double {
        let f = try await exchange(d,rebuild:rebuild,prepare:prepare) { if case .sent = $0 { return true }; return false }
        guard case .sent(let receipt) = f else { throw MeshError.invalid("potvrzení odeslání") }
        onProgress?("Companion přijal požadavek k odeslání po LoRa. Čekám na repeater…")
        return min(180, max(10, Double(receipt.timeout)/1000+5))
    }
    public func login(key: Data, password: String) async throws -> UInt8 {
        try await operation {
            remote.removeAll()
            let timeout = try await send(MeshCodec.login(key:key, password:password))
            let f = try await waitRemote(timeout:timeout) {
                switch $0 { case .login(let p,_), .loginFailed(let p): return p == key.prefix(6); default:return false }
            }
            guard case .login(_,let permissions) = f else { throw MeshError.remote("Repeater odmítl přihlášení. Zkontrolujte heslo.") }
            return permissions
        }
    }
    public func status(key: Data, onSend: (() -> Void)? = nil) async throws -> RepeaterStatus {
        try await operation {
            remote.removeAll()
            let timeout = try await send(Data([27])+key,rebuild:{ onSend?(); return Data([27])+key })
            let f = try await waitRemote(timeout:timeout) { if case .status(let p,_) = $0 { return p == key.prefix(6) }; return false }
            guard case .status(_,let s) = f else { throw MeshError.invalid("statistiky") }; return s
        }
    }
    /// CMD_SEND_BINARY_REQ (50). Responses echo the SENT tag; firmware authenticates the peer.
    public func binary(key: Data, payload: Data) async throws -> Data {
        guard key.count == 32, !payload.isEmpty, payload.count <= 140 else { throw MeshError.invalid("binární požadavek") }
        return try await operation {
            remote.removeAll()
            let f = try await exchange(Data([50])+key+payload) { if case .sent = $0 { return true }; return false }
            guard case .sent(let receipt) = f else { throw MeshError.invalid("tag binárního požadavku") }
            onProgress?("Požadavek přijal companion. Čekám na odpověď repeateru…")
            let reply = try await waitRemote(timeout:min(180,max(10,Double(receipt.timeout)/1000+5))) { if case .binary(let tag,_) = $0 { return tag == receipt.acknowledgement }; return false }
            guard case .binary(_,let data) = reply else { throw MeshError.invalid("binární odpověď") }; return data
        }
    }
    public func cli(key: Data, command: String, noReply: Bool = false, commandAtSend: (() -> String)? = nil) async throws -> String {
        try await operation {
            var actualCommand = command
            let timeout = try await send(MeshCodec.cli(key:key, command:command, timestamp:UInt32(Date().timeIntervalSince1970)),rebuild:{
                actualCommand = commandAtSend?() ?? command
                return try MeshCodec.cli(key:key,command:actualCommand,timestamp:UInt32(Date().timeIntervalSince1970))
            },prepare:{ try await self.drain() })
            if noReply { return "Požadavek přijal companion. Tento příkaz neposílá odpověď; provedení není potvrzeno." }
            let f = try await waitRemote(timeout:timeout, poll:true) { if case .message(let m) = $0 { return m.prefix == key.prefix(6) && m.type == 1 }; return false }
            guard case .message(let m) = f else { throw MeshError.invalid("CLI odpověď") }
            onCLIReply?(key,actualCommand,m.text); return m.text
        }
    }
}
