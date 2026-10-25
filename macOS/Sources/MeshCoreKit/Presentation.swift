import Foundation

public enum ContactScope: String, CaseIterable, Identifiable {
    case all = "Všechny", repeaters = "Repeatery", companions = "Companiony", rooms = "Room servery", unstored = "Nově objevené"
    public var id: String { rawValue }
    public func includes(_ c: Contact) -> Bool {
        switch self { case .all:return true; case .repeaters:return c.kind == 2; case .companions:return c.kind == 1; case .rooms:return c.kind == 3; case .unstored:return !c.stored }
    }
}
public enum ContactQuery {
    public static func filter(_ contacts: [Contact], search: String, scope: ContactScope) -> [Contact] {
        let terms = search.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return contacts.filter { c in
            scope.includes(c) && terms.allSatisfy { term in
                c.name.localizedStandardContains(term) || c.id.localizedCaseInsensitiveContains(term) || c.kindName.localizedStandardContains(term)
            }
        }
    }
}
public enum MeshPresentation {
    public static func route(_ contact: Contact) -> String {
        let length = contact.outPathLength
        if length == 255 { return "Flood · cesta neznámá" }
        let size = Int(length >> 6) + 1, count = Int(length & 63)
        guard size <= 3, size * count <= contact.outPath.count else { return "Neplatná cesta" }
        if count == 0 { return "Přímá cesta" }
        return "\(count) \(count == 1 ? "hop" : (count < 5 ? "hopy" : "hopů")) · \(size) B/hash"
    }
    public static func duration(_ seconds: UInt32) -> String {
        let d = seconds / 86400, h = (seconds % 86400) / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        if d > 0 { return "\(d) d \(h) h \(m) min" }
        if h > 0 { return "\(h) h \(m) min" }
        if m > 0 { return "\(m) min \(s) s" }
        return "\(s) s"
    }
    public static func sameValue(key: String, _ lhs: String, _ rhs: String) -> Bool {
        let a = lhs.trimmingCharacters(in:.whitespacesAndNewlines), b = rhs.trimmingCharacters(in:.whitespacesAndNewlines)
        if key == "radio" {
            guard a.split(separator:",",omittingEmptySubsequences:false).count == 4, b.split(separator:",",omittingEmptySubsequences:false).count == 4 else { return false }
            let x = a.split(separator:",").compactMap { Double($0.trimmingCharacters(in:.whitespaces)) }
            let y = b.split(separator:",").compactMap { Double($0.trimmingCharacters(in:.whitespaces)) }
            return x.count == 4 && y.count == 4 && zip(x,y).allSatisfy { $0.isFinite && $1.isFinite && abs($0-$1) < 0.000001 }
        }
        if key == "dutycycle", let x = Double(a.replacingOccurrences(of:"%",with:"")), let y = Double(b.replacingOccurrences(of:"%",with:"")) { return x.isFinite && y.isFinite && abs(x-y) < 0.051 }
        if ["lat","lon","tx","advert.interval","flood.advert.interval","af","path.hash.mode","flood.max","flood.max.advert","flood.max.unscoped"].contains(key), let x = Double(a), let y = Double(b) { return x.isFinite && y.isFinite && abs(x-y) < 0.000001 }
        return a == b
    }
}

public struct RadioDraft: Equatable {
    public var frequency: String
    public var bandwidth: String
    public var spreadingFactor: String
    public var codingRate: String
    public init(_ raw: String) {
        let parts = raw.split(separator:",",omittingEmptySubsequences:false).map { $0.trimmingCharacters(in:.whitespaces) }
        frequency = parts.first ?? ""; bandwidth = parts.count > 1 ? parts[1] : ""
        spreadingFactor = parts.count > 2 ? parts[2] : ""; codingRate = parts.count > 3 ? parts[3] : ""
        if let b = Double(bandwidth), b.isFinite { bandwidth = String(format:"%g",locale:Locale(identifier:"en_US_POSIX"),b) }
    }
    public var rawValue: String { [frequency,bandwidth,spreadingFactor,codingRate].joined(separator:",") }
}

public struct CommandHistoryNavigator {
    private var index = -1
    private var draft = ""
    public init() {}
    public mutating func previous(current: String, history: [String]) -> String {
        guard !history.isEmpty else { return current }
        if index == -1 { draft = current }
        index = min(index + 1,history.count - 1)
        return history[index]
    }
    public mutating func next(current: String, history: [String]) -> String {
        guard index >= 0 else { return current }
        guard !history.isEmpty else { index = -1; return draft }
        index -= 1
        return index < 0 ? draft : history[min(index,history.count - 1)]
    }
    public mutating func reset() { index = -1; draft = "" }
}
