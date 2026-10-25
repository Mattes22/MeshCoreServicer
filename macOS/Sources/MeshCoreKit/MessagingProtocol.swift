import Foundation
import CryptoKit
import CommonCrypto

public struct SendReceipt: Equatable, Sendable {
    public let flood: Bool
    public let acknowledgement: UInt32
    public let timeout: UInt32
    public init(flood: Bool, acknowledgement: UInt32, timeout: UInt32) { self.flood = flood; self.acknowledgement = acknowledgement; self.timeout = timeout }
}
public struct ChannelInfo: Equatable, Sendable, CustomStringConvertible {
    public let index: UInt8
    public let name: String
    public let fingerprint: String
    public let configured: Bool
    private let secret: Data
    public var displayName: String { name.isEmpty ? "Kanál \(index)" : name }
    public var id: String { "channel:\(index):\(fingerprint)" }
    public var description: String { "ChannelInfo(index: \(index), name: \(name))" }
    public init(index: UInt8, name: String, secret: Data) throws {
        guard secret.count == 16 else { throw MeshError.invalid("128bitový klíč kanálu") }
        self.index = index; self.name = name; self.secret = secret
        fingerprint = Data(SHA256.hash(data:secret)).hex
        configured = !name.isEmpty || secret.contains { $0 != 0 }
    }
    /// Reproduces the pinned firmware's group packet payload for exact, path-independent RX matching.
    /// Keys remain in memory; neither the secret nor ciphertext is included in the returned identifier.
    public func packetFingerprint(timestamp: UInt32, wireText: String) throws -> String {
        guard configured, !wireText.utf8.contains(0), wireText.utf8.count <= 160 else { throw MeshError.invalid("text skupinového paketu") }
        var plain = Data(); plain.appendLE(timestamp); plain.append(0); plain.append(Data(wireText.utf8))
        if plain.count % 16 != 0 { plain.append(Data(repeating:0,count:16-plain.count%16)) }
        var encrypted = Data(count:plain.count), written = 0
        let capacity = encrypted.count
        let result = secret.withUnsafeBytes { key in plain.withUnsafeBytes { input in encrypted.withUnsafeMutableBytes { output in
            CCCrypt(CCOperation(kCCEncrypt),CCAlgorithm(kCCAlgorithmAES),CCOptions(kCCOptionECBMode),key.baseAddress,16,nil,input.baseAddress,plain.count,output.baseAddress,capacity,&written)
        } } }
        guard result == kCCSuccess, written == plain.count else { throw MeshError.invalid("výpočet otisku paketu") }
        var hmacKey = secret; hmacKey.append(Data(repeating:0,count:16))
        let mac = Data(HMAC<SHA256>.authenticationCode(for:encrypted,using:SymmetricKey(data:hmacKey))).prefix(2)
        var packet = Data([5,Data(SHA256.hash(data:secret))[0]]); packet.append(mac); packet.append(encrypted)
        return Data(SHA256.hash(data:packet)).hex
    }
}
public struct ChannelMessage: Equatable, Sendable {
    public let index: UInt8
    public let pathLength: UInt8
    public let type: UInt8
    public let timestamp: UInt32
    public let text: String
    public let snr: Double?
    public var identity: String { "channel:\(index):\(timestamp):\(type):\(text)" }
    public var hops: Int? { MeshMessaging.hops(pathLength) }
}
public struct GroupObservation: Equatable, Sendable {
    public let fingerprint: String
    public let hops: Int?
    public let rssi: Int8
    public let snr: Double
    public static func decode(raw: Data, rssi: Int8, snr: Double) throws -> Self? {
        var r = Reader(raw)
        let header = try r.u8(), route = header & 3
        guard header >> 6 == 0, (header >> 2) & 15 == 5 else { return nil }
        if route == 0 || route == 3 { _ = try r.data(4) }
        let path = try r.u8(), size = Int(path >> 6)+1, count = Int(path & 63)
        guard size <= 3, size * count <= 64 else { throw MeshError.invalid("cesta rádiového paketu") }
        _ = try r.data(size * count)
        let payload = try r.data(r.bytes.count-r.offset)
        guard payload.count >= 19, (payload.count-3) % 16 == 0 else { throw MeshError.invalid("skupinový payload") }
        return Self(fingerprint:Data(SHA256.hash(data:Data([5])+payload)).hex,hops:(route == 0 || route == 1) ? count : nil,rssi:rssi,snr:snr)
    }
}
public enum MeshMessaging {
    public static let maximumTextBytes = 133
    public static func channelLimit(sender: String) -> Int { max(0,min(maximumTextBytes,160-sender.utf8.count-2)) }
    public static func hops(_ encoded: UInt8) -> Int? {
        if encoded == 255 { return nil }
        let count = Int(encoded & 63), size = Int(encoded >> 6)+1
        return size <= 3 && count * size <= 64 ? count : nil
    }
    public static func validate(_ text: String, limit: Int = maximumTextBytes) throws {
        guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, !text.utf8.contains(0), text.utf8.count <= limit else { throw MeshError.invalid("zpráva musí mít 1 až \(limit) UTF-8 bajtů a nesmí obsahovat NUL") }
    }
    public static func direct(key: Data, text: String, timestamp: UInt32) throws -> Data {
        try validate(text)
        guard key.count == 32 else { throw MeshError.invalid("veřejný klíč příjemce") }
        var d = Data([2,0,0]); d.appendLE(timestamp); d.append(key.prefix(6)); d.append(Data(text.utf8)); return d
    }
    public static func channel(index: UInt8, text: String, sender: String, timestamp: UInt32) throws -> Data {
        try validate(text,limit:channelLimit(sender:sender))
        var d = Data([3,0,index]); d.appendLE(timestamp); d.append(Data(text.utf8)); return d
    }
}
