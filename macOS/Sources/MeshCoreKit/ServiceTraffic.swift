import Foundation

public struct ServiceOperationCancelled: LocalizedError {
    public var errorDescription: String? { "Servisní požadavek byl zrušen před odesláním: změna relace, oprávnění nebo zastavení měření." }
    public init() {}
}

public enum ServiceRoute: Equatable, Sendable {
    case known, floodOrUnknown
    public static func classify(path: UInt8?, bytes: Int = 64) -> Self {
        guard let path, path != 255, path >> 6 < 3, Int(path & 63) * (Int(path >> 6)+1) <= bytes else { return .floodOrUnknown }
        return .known
    }
}

/// One application-wide service budget, retained across BLE resets and node switches.
/// Local BLE reads and chat do not consume it. No requests are queued here.
@MainActor public final class ServiceTrafficGovernor {
    private let now: () -> Date
    private let delay: (Double) async throws -> Void
    private var sent: [(Date,ServiceRoute)] = []
    private var last: (Date,ServiceRoute)?
    private var scopeStart: Date?
    private var scopeCount = 0
    private var valid: (() -> Bool)?
    public init(now: @escaping () -> Date = Date.init, delay: @escaping (Double) async throws -> Void = { try await Task.sleep(nanoseconds:UInt64($0*1e9)) }) { self.now = now; self.delay = delay }
    public func begin(valid: @escaping () -> Bool) throws {
        guard scopeStart == nil else { throw MeshError.busy }
        scopeStart = now(); scopeCount = 0; self.valid = valid
    }
    public func confirmFlood() {
        guard let last, !sent.isEmpty else { return }
        self.last = (last.0,.floodOrUnknown); sent[sent.count-1] = (last.0,.floodOrUnknown)
    }
    public func end() { scopeStart = nil; scopeCount = 0; valid = nil }
    public func validateContext() throws {
        if let start = scopeStart, now().timeIntervalSince(start) > 1200 { throw MeshError.remote("Vypršel dvacetiminutový limit servisní operace; další krok se neposlal.") }
        guard valid?() != false else { throw ServiceOperationCancelled() }
        try Task.checkCancellation()
    }
    private func check(_ route: ServiceRoute) throws {
        let time = now()
        if let start = scopeStart, time.timeIntervalSince(start) > 1200 || scopeCount >= 32 { throw MeshError.remote("Servisní operace dosáhla limitu 32 požadavků nebo 20 minut. Zbývající kroky se neposlaly; načtěte stav ručně.") }
        guard valid?() != false else { throw ServiceOperationCancelled() }
        if let last, time < last.0 { throw MeshError.remote("Systémový čas se posunul zpět; servisní požadavek se neposlal.") }
        sent.removeAll { time.timeIntervalSince($0.0) >= 3600 }
        let lane = route == .known ? sent : sent.filter { $0.1 == .floodOrUnknown }
        if sent.count >= 60 || route != .known && lane.count >= 12 {
            let first = sent.count >= 60 ? sent[0].0 : lane[0].0
            let wait = Int(ceil(max(1,3600-time.timeIntervalSince(first))))
            throw MeshError.remote("Limit sdílené LoRa sítě: nejvýše 60 servisních požadavků/h, z toho 12 bez známé trasy. Zkuste ručně za \(wait) s. Požadavek nebyl zařazen do fronty.")
        }
    }
    public func acquire(route: ServiceRoute, progress: ((String)->Void)? = nil) async throws {
        try check(route)
        if let last {
            let gap: Double = route == .known && last.1 == .known ? 15 : 60
            let wait = gap-now().timeIntervalSince(last.0)
            if wait > 0 { progress?("Šetřím LoRa síť: další servisní krok nejdříve za \(Int(ceil(wait))) s (\(route == .known ? "uložená trasa" : "flood / neznámá trasa")). Fronta dalších operací není vytvářena."); try await delay(wait) }
        }
        try Task.checkCancellation(); try check(route)
        last = (now(),route); sent.append(last!); scopeCount += 1
    }
}

public struct DiagnosticPlan: Equatable, Sendable {
    // Application policy for scheduled diagnostics, independent of manual service pacing.
    public static let defaultIntervalMinutes = 240
    public static let defaultSamples = 3
    public static let minimumIntervalMinutes = 180
    public static let maximumIntervalMinutes = 1440
    public static let maximumSamples = 6
    public static let maximumDurationMinutes = 1440
    public static func hoursText(_ minutes: Int) -> String {
        "\(minutes/60) h" + (minutes % 60 == 0 ? "" : " \(minutes % 60) min")
    }
    public let intervalMinutes: Int
    public let samples: Int
    public var durationMinutes: Int { intervalMinutes*samples }
    public init(intervalMinutes: Int = Self.defaultIntervalMinutes, samples: Int = Self.defaultSamples, route: ServiceRoute) throws {
        guard (Self.minimumIntervalMinutes...Self.maximumIntervalMinutes).contains(intervalMinutes), (1...Self.maximumSamples).contains(samples), intervalMinutes*samples <= Self.maximumDurationMinutes else { throw MeshError.invalid("měření: interval 3–24 hodin, 1–6 vzorků, celkem nejvýše 24 hodin") }
        self.intervalMinutes = intervalMinutes; self.samples = samples
    }
}

/// Fixed slots, 30 s scheduling tolerance. Late/busy slots are skipped, never replayed.
public struct DiagnosticMeasurement: Equatable, Sendable {
    public let id = UUID()
    public let plan: DiagnosticPlan
    public let start: Date
    public private(set) var consumed = 0
    public private(set) var received = 0
    public private(set) var skipped = 0
    public private(set) var running = true
    public private(set) var inFlight = false
    public private(set) var transmitted = false
    public var remaining: Int { plan.samples-consumed }
    public var next: Date? { running && remaining > 0 ? start.addingTimeInterval(Double((consumed+1)*plan.intervalMinutes*60)) : nil }
    public init(plan: DiagnosticPlan, start: Date = Date()) { self.plan = plan; self.start = start }
    public mutating func takeDue(now: Date, busy: Bool) -> Bool {
        if now < start { running = false; return false }
        guard running, !inFlight, let next, now >= next else { return false }
        if now.timeIntervalSince(next) > 30 {
            let missed = min(remaining,Int(now.timeIntervalSince(next)/Double(plan.intervalMinutes*60))+1)
            consumed += missed; skipped += missed
        } else {
            consumed += 1
            if busy { skipped += 1 } else { inFlight = true; return true }
        }
        if remaining == 0 { running = false }; return false
    }
    public mutating func markTransmitted() { if inFlight { transmitted = true } }
    public mutating func finish(success: Bool) {
        guard inFlight else { return }; inFlight = false; transmitted = false
        if success { received += 1 } else { running = false }
        if remaining == 0 { running = false }
    }
    public mutating func stop() { running = false }
}
