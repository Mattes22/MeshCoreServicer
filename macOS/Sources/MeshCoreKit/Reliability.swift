import Foundation

public struct ReconnectPolicy: Equatable, Sendable {
    public var enabled = true
    public private(set) var wanted = false
    public private(set) var attempt = 0
    public init() {}
    public mutating func userConnect() { wanted = true; attempt = 0 }
    public mutating func userDisconnect() { wanted = false; attempt = 0 }
    public mutating func connected() { attempt = 0 }
    public mutating func nextDelay(poweredOn: Bool, sleeping: Bool) -> Double? {
        guard enabled, wanted, poweredOn, !sleeping else { return nil }
        let delay = min(30,pow(2,Double(min(attempt,5)))); attempt += 1; return delay
    }
}
public struct PacketCapture: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let hops: Int?
    public let rssi: Int8
    public let snr: Double
    public var forwarded: Bool { (hops ?? 0) > 0 }
    public init(date: Date = Date(), hops: Int?, rssi: Int8, snr: Double) { id = UUID(); self.date = date; self.hops = hops; self.rssi = rssi; self.snr = snr }
}
public struct ConfigSnapshot: Identifiable, Codable, Equatable, Sendable {
    public var version = 1
    public var id = UUID()
    public let account: String
    public let repeater: String
    public let name: String
    public let date: Date
    public let readAt: [String:Date]?
    public let values: [String:String]
    public init(account: String, repeater: String, name: String, date: Date = Date(), values: [String:String], readAt: [String:Date] = [:]) throws {
        self.account = account; self.repeater = repeater; self.name = name; self.date = date; self.values = values; self.readAt = readAt
        try validate()
    }
    public func validate() throws {
        _ = try RepeaterCommand.publicKey(account); _ = try RepeaterCommand.publicKey(repeater)
        guard version == 1, !values.isEmpty, values.count <= CLIValidation.keys.count, name.utf8.count <= 128 else { throw MeshError.invalid("snímek konfigurace") }
        guard !(values["dutycycle"] != nil && values["af"] != nil) else { throw MeshError.invalid("snímek obsahuje zároveň dutycycle a af") }
        guard Set(readAt?.keys.map{$0} ?? []).isSubset(of:Set(values.keys)) else { throw MeshError.invalid("časy čtení snímku") }
        guard date.timeIntervalSince1970.isFinite, (readAt ?? [:]).values.allSatisfy({ $0.timeIntervalSince1970.isFinite && $0 <= date.addingTimeInterval(1) }) else { throw MeshError.invalid("datum snímku") }
        for (key,value) in values { _ = try CLIValidation.validate(key:key,value:value) }
    }
    public func differences(current: [String:String]) -> [String] { CLIValidation.keys.filter { key in values[key].map { value in current[key].map { !MeshPresentation.sameValue(key:key,$0,value) } ?? false } ?? false } }
}
public struct HealthSample: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public let date: Date
    public let battery: UInt16
    public let uptime: UInt32
    public let received: UInt32
    public let sent: UInt32
    public let rssi: Int16
    public let snr: Double
    public let noise: Int16
    public init(status: RepeaterStatus, date: Date = Date()) { self.date = date; battery = status.battery; uptime = status.uptime; received = status.received; sent = status.sent; rssi = status.lastRSSI; snr = status.lastSNR; noise = status.noiseFloor }
    public func suggestsRestart(after older: Self) -> Bool { date > older.date && uptime < older.uptime }
}
public struct RestartReview: Codable, Equatable, Sendable {
    public let date: Date
    public let reason: String
    public var reachable: Date?
    public var clockChecked: Date?
    public init(date: Date = Date(), reason: String) { self.date = date; self.reason = reason }
}
public struct UnverifiedChange: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public let key: String
    public let date: Date
    public let expected: String?
    public init(key: String, date: Date = Date(), expected: String? = nil) { self.key = key; self.date = date; self.expected = expected }
}
