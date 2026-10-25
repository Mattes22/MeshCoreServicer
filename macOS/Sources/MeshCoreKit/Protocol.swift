import Foundation

public enum MeshError: LocalizedError {
    case invalid(String), timeout, disconnected, busy, remote(String), uncertain
    public var errorDescription: String? {
        switch self {
        case .invalid(let s): return "Neplatná data: \(s)"
        case .timeout: return "Vypršel čas odpovědi. Výsledek požadavku není známý."
        case .disconnected: return "Companion není připojen."
        case .busy: return "Probíhá jiný požadavek."
        case .remote(let s): return s
        case .uncertain: return "Po předchozím timeoutu nelze bezpečně přiřadit další odpověď. Odpojte a znovu připojte companion. Před opakováním změny načtěte její stav."
        }
    }
}

public extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
    mutating func appendLE(_ value: UInt32) { append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }
}

struct Reader {
    let bytes: [UInt8]
    var offset = 0
    init(_ data: Data) { bytes = Array(data) }
    mutating func data(_ count: Int) throws -> Data {
        guard count >= 0, offset + count <= bytes.count else { throw MeshError.invalid("zkrácený rámec") }
        defer { offset += count }; return Data(bytes[offset..<offset+count])
    }
    mutating func u8() throws -> UInt8 { try data(1).first! }
    mutating func i8() throws -> Int8 { Int8(bitPattern: try u8()) }
    mutating func u16() throws -> UInt16 { let b = Array(try data(2)); return UInt16(b[0]) | UInt16(b[1]) << 8 }
    mutating func i16() throws -> Int16 { Int16(bitPattern: try u16()) }
    mutating func u32() throws -> UInt32 { let b = Array(try data(4)); return b.enumerated().reduce(0) { $0 | UInt32($1.element) << ($1.offset*8) } }
    mutating func i32() throws -> Int32 { Int32(bitPattern: try u32()) }
    mutating func string(_ count: Int? = nil) throws -> String {
        let d = try data(count ?? (bytes.count-offset)); return String(decoding: d.prefix(while: { $0 != 0 }), as: UTF8.self)
    }
}

public struct Contact: Identifiable, Equatable, Sendable {
    public let key: Data
    public var kind: UInt8
    public var name: String
    public let lastAdvert: UInt32
    public let latitude: Double
    public let longitude: Double
    public var flags: UInt8 = 0
    public var outPathLength: UInt8 = 255
    public var outPath = Data(repeating:0,count:64)
    public var stored: Bool
    public var id: String { key.hex }
    public var kindName: String { [1:"Companion", 2:"Repeater", 3:"Room server", 4:"Senzor"][kind] ?? "Neznámý uzel" }
    public init(key: Data, kind: UInt8, name: String, lastAdvert: UInt32 = 0, latitude: Double = 0, longitude: Double = 0, stored: Bool = false) {
        self.key = key; self.kind = kind; self.name = name; self.lastAdvert = lastAdvert; self.latitude = latitude; self.longitude = longitude; self.stored = stored
    }
}
public struct SelfInfo: Equatable, Sendable {
    public let key: Data
    public let name: String
    public let frequency: Double
    public let bandwidth: Double
    public let sf: UInt8
    public let cr: UInt8
}
public struct DeviceInfo: Equatable, Sendable {
    public let maxChannels: UInt8
    public let protocolVersion: UInt8
    public let build: String
    public let model: String
    public let version: String
}
public struct CLIMessage: Equatable, Sendable {
    public let prefix: Data
    public let type: UInt8
    public let timestamp: UInt32
    public let text: String
    public let snr: Double?
    public var pathLength: UInt8 = 255
    public var senderPrefix: Data? = nil
    public var identity: String { "\(prefix.hex):\(timestamp):\(type):\(senderPrefix?.hex ?? ""):\(text)" }
}
public struct RepeaterStatus: Equatable, Sendable {
    public let battery: UInt16
    public let queue: UInt16
    public let noiseFloor: Int16
    public let lastRSSI: Int16
    public let received: UInt32
    public let sent: UInt32
    public let txAirtime: UInt32
    public let uptime: UInt32
    public let lastSNR: Double
    public let sentFlood: UInt32
    public let sentDirect: UInt32
    public let receivedFlood: UInt32
    public let receivedDirect: UInt32
    public let errorEvents: UInt16
    public let directDuplicates: UInt16
    public let floodDuplicates: UInt16
    public let rxAirtime: UInt32?
    public let receiveErrors: UInt32?
    public static func decode(_ data: Data) throws -> Self {
        var r = Reader(data)
        let b = try r.u16(), q = try r.u16(), n = try r.i16(), signal = try r.i16()
        let rx = try r.u32(), tx = try r.u32(), air = try r.u32(), up = try r.u32()
        let sf = try r.u32(), sd = try r.u32(), rf = try r.u32(), rd = try r.u32(), events = try r.u16()
        let snr = Double(try r.i16()) / 4
        let dd = try r.u16(), fd = try r.u16()
        let rxAir = r.bytes.count-r.offset >= 4 ? try r.u32() : nil
        let errors = r.bytes.count-r.offset >= 4 ? try r.u32() : nil
        return Self(battery:b, queue:q, noiseFloor:n, lastRSSI:signal, received:rx, sent:tx, txAirtime:air, uptime:up, lastSNR:snr, sentFlood:sf, sentDirect:sd, receivedFlood:rf, receivedDirect:rd, errorEvents:events, directDuplicates:dd, floodDuplicates:fd, rxAirtime:rxAir, receiveErrors:errors)
    }
}
public struct Discovery: Equatable, Sendable {
    public let key: Data
    public let tag: UInt32
    public let kind: UInt8
    public let companionRSSI: Int8
    public let companionSNR: Double
    public let repeaterSNR: Double
}
public enum Frame: Equatable, Sendable {
    case ok, error(UInt8), contactsStart(UInt32), contact(Contact), contactsEnd
    case selfInfo(SelfInfo), deviceInfo(DeviceInfo), battery(UInt16)
    case sent(SendReceipt), login(prefix: Data, permissions: UInt8), loginFailed(Data)
    case status(prefix: Data, RepeaterStatus), message(CLIMessage), noMessages, messagesWaiting
    case channelInfo(ChannelInfo), channelMessage(ChannelMessage), acknowledgement(code: UInt32, roundTrip: UInt32), groupObservation(GroupObservation)
    case binary(tag: UInt32, payload: Data)
    case advert(Data), discovery(Discovery), other(UInt8)
}

public enum MeshCodec {
    public static let serviceUUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    public static let rxUUID = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    public static let txUUID = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
    // BLE has no serial '<' / '>' envelope and no length prefix.
    public static func bleFrame(_ data: Data, maximumWriteLength: Int = 176) throws -> Data {
        guard !data.isEmpty, data.count <= 176, data.count <= maximumWriteLength else { throw MeshError.invalid("rámec se nevejde do jednoho BLE zápisu; fragmentace není podporována") }
        return data
    }
    public static func addContact(_ c: Contact) throws -> Data {
        guard c.key.count == 32, c.outPath.count == 64 else { throw MeshError.invalid("kontakt") }
        var d = Data([9]) + c.key + Data([c.kind,c.flags,c.outPathLength]) + c.outPath
        var name = Data(c.name.utf8.prefix(31)); name.append(Data(repeating:0,count:32-name.count)); d.append(name)
        d.appendLE(c.lastAdvert); d.appendLE(UInt32(bitPattern:Int32(c.latitude*1e6))); d.appendLE(UInt32(bitPattern:Int32(c.longitude*1e6)))
        return d // omit optional lastmod: companion uses its own RTC
    }
    public static func appStart() -> Data { Data([1,1,0,0,0,0,0,0]) + Data("MeshCore Servicer".utf8) }
    public static func login(key: Data, password: String) throws -> Data {
        guard key.count == 32, password.utf8.count <= 15, !password.utf8.contains(0) else { throw MeshError.invalid("klíč musí mít 32 bajtů, heslo nejvýše 15 bajtů") }
        return Data([26]) + key + Data(password.utf8)
    }
    public static func cli(key: Data, command: String, timestamp: UInt32) throws -> Data {
        guard key.count == 32, !command.isEmpty, command.utf8.count <= 133, !command.contains(where: { $0.isNewline }), !command.utf8.contains(0) else { throw MeshError.invalid("CLI příkaz musí být jeden řádek do 133 UTF-8 bajtů") }
        var d = Data([2,1,0]); d.appendLE(timestamp); d.append(key.prefix(6)); d.append(Data(command.utf8)); return d
    }
    public static func discover(tag: UInt32) -> Data { var d = Data([55,0x80,0x04]); d.appendLE(tag); return d }
    public static func decode(_ data: Data) throws -> Frame {
        _ = try bleFrame(data)
        var r = Reader(data); let code = try r.u8()
        switch code {
        case 0x8c:
            _ = try r.u8(); let tag = try r.u32(); return .binary(tag:tag,payload:try r.data(r.bytes.count-r.offset))
        case 0: return .ok
        case 1: return .error(data.count > 1 ? try r.u8() : 0)
        case 2: return .contactsStart(try r.u32())
        case 3, 0x8a:
            let key = try r.data(32), kind = try r.u8(), flags = try r.u8(), pathLength = try r.u8(), path = try r.data(64)
            let name = try r.string(32), adv = try r.u32(), lat = try r.i32(), lon = try r.i32()
            _ = try r.u32()
            var c = Contact(key:key, kind:kind, name:name, lastAdvert:adv, latitude:Double(lat)/1e6, longitude:Double(lon)/1e6, stored:code == 3)
            c.flags = flags; c.outPathLength = pathLength; c.outPath = path
            return .contact(c)
        case 4: _ = try r.u32(); return .contactsEnd
        case 5:
            _ = try r.data(3); let key = try r.data(32); _ = try r.data(12); let f = try r.u32(), b = try r.u32(), sf = try r.u8(), cr = try r.u8()
            return .selfInfo(SelfInfo(key:key, name:try r.string(), frequency:Double(f)/1000, bandwidth:Double(b)/1000, sf:sf, cr:cr))
        case 6: let flood = try r.u8() != 0, ack = try r.u32(); return .sent(SendReceipt(flood:flood, acknowledgement:ack, timeout:try r.u32()))
        case 7,16:
            var snr: Double? = nil
            if code == 16 { snr = Double(try r.i8())/4; _ = try r.data(2) }
            let prefix = try r.data(6); let path = try r.u8(); let type = try r.u8(), time = try r.u32()
            let sender = type == 2 ? try r.data(4) : nil
            return .message(CLIMessage(prefix:prefix, type:type, timestamp:time, text:try r.string(), snr:snr, pathLength:path, senderPrefix:sender))
        case 8,17:
            var snr: Double? = nil
            if code == 17 { snr = Double(try r.i8())/4; _ = try r.data(2) }
            let index = try r.u8(), path = try r.u8(), type = try r.u8(), time = try r.u32()
            return .channelMessage(ChannelMessage(index:index,pathLength:path,type:type,timestamp:time,text:try r.string(),snr:snr))
        case 18:
            let index = try r.u8(), name = try r.string(32), secret = try r.data(16)
            return .channelInfo(try ChannelInfo(index:index,name:name,secret:secret))
        case 0x82: return .acknowledgement(code:try r.u32(),roundTrip:try r.u32())
        case 0x88:
            let snr = Double(try r.i8())/4, rssi = try r.i8()
            if let group = try GroupObservation.decode(raw:r.data(r.bytes.count-r.offset),rssi:rssi,snr:snr) { return .groupObservation(group) }
            return .other(code)
        case 10: return .noMessages
        case 12: return .battery(try r.u16())
        case 13:
            let version = try r.u8()
            guard version >= 3 else { return .deviceInfo(DeviceInfo(maxChannels:0, protocolVersion:version, build:"", model:"", version:"")) }
            _ = try r.u8(); let channels = try r.u8(); _ = try r.data(4) // BLE PIN is never exposed or logged
            return .deviceInfo(DeviceInfo(maxChannels:channels, protocolVersion:version, build:try r.string(12), model:try r.string(40), version:try r.string(20)))
        case 0x80,0x81: return .advert(try r.data(32))
        case 0x83: return .messagesWaiting
        case 0x85: let p = try r.u8(); return .login(prefix:try r.data(6), permissions:p)
        case 0x86: _ = try r.u8(); return .loginFailed(try r.data(6))
        case 0x87: _ = try r.u8(); let key = try r.data(6); return .status(prefix:key, try RepeaterStatus.decode(r.data(r.bytes.count-r.offset)))
        case 0x8e:
            let snr = Double(try r.i8())/4, rssi = try r.i8(); _ = try r.u8()
            let flags = try r.u8(); guard flags & 0xf0 == 0x90 else { return .other(code) }
            let remoteSNR = Double(try r.i8())/4, tag = try r.u32(), key = try r.data(r.bytes.count-r.offset)
            guard key.count == 8 || key.count == 32 else { throw MeshError.invalid("délka discovery klíče") }
            return .discovery(Discovery(key:key, tag:tag, kind:flags & 15, companionRSSI:rssi, companionSNR:snr, repeaterSNR:remoteSNR))
        default: return .other(code)
        }
    }
}
