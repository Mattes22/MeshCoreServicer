import Foundation
public enum CLIValidation {
    public static let basicKeys = ["name", "lat", "lon", "tx", "radio", "advert.interval", "flood.advert.interval", "repeat"]
    public static let networkKeys = ["dutycycle", "af", "path.hash.mode", "flood.max", "flood.max.advert", "flood.max.unscoped", "loop.detect"]
    public static let keys = basicKeys + ["owner.info"] + networkKeys
    public static func sensitive(_ command: String) -> Bool {
        let s = command.lowercased()
        return ["password", "prv", "private", "secret", "pin", "key"].contains { s.contains($0) }
    }
    public static func needsRadioWarning(_ command: String) -> Bool {
        let c = command.lowercased().trimmingCharacters(in:.whitespaces)
        return ["set radio ","set freq ","tempradio "].contains { c.hasPrefix($0) }
    }
    public static func needsRestartConfirmation(_ command: String) -> Bool {
        let c = command.lowercased().trimmingCharacters(in:.whitespaces)
        return ["reboot","clkreboot","poweroff","shutdown"].contains { c.hasPrefix($0) }
    }
    public static func validate(key: String, value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in:.whitespaces)
        let v = key == "dutycycle" && trimmed.hasSuffix("%") ? String(trimmed.dropLast()) : trimmed
        guard !v.isEmpty, !v.contains(where: { $0.isNewline }), !v.utf8.contains(0) else { throw MeshError.invalid("prázdná nebo víceřádková hodnota") }
        func number(_ lo: Double, _ hi: Double) -> Bool { guard let n = Double(v), n.isFinite else { return false }; return n >= lo && n <= hi }
        var valid = false
        switch key {
        case "name": valid = v.utf8.count <= 23 && !v.contains("|")
        case "lat": valid = number(-90,90)
        case "lon": valid = number(-180,180)
        case "tx": valid = Int(v).map { (1...22).contains($0) } ?? false
        case "repeat": valid = ["on","off"].contains(v)
        case "owner.info": valid = v.utf8.count <= 118
        case "dutycycle": valid = number(1,100)
        case "af": valid = number(0,9)
        case "path.hash.mode": valid = ["0","1","2"].contains(v)
        case "flood.max", "flood.max.advert", "flood.max.unscoped": valid = Int(v).map { (0...64).contains($0) } ?? false
        case "loop.detect": valid = ["off","minimal","moderate","strict"].contains(v)
        case "advert.interval": valid = Int(v).map { $0 == 0 || ((60...240).contains($0) && $0 % 2 == 0) } ?? false
        case "flood.advert.interval": valid = Int(v).map { $0 == 0 || (3...168).contains($0) } ?? false
        case "radio":
            let p = v.split(separator:",", omittingEmptySubsequences:false).map(String.init)
            if p.count == 4, let f = Double(p[0]), let b = Double(p[1]), let sf = Int(p[2]), let cr = Int(p[3]) {
                valid = f.isFinite && b.isFinite && (150...2500).contains(f) && [7.8,10.4,15.6,20.8,31.25,41.7,62.5,125,250,500].contains(b) && (5...12).contains(sf) && (5...8).contains(cr)
            }
        default: break
        }
        guard valid else { throw MeshError.invalid("hodnota pro \(key); použijte desetinnou tečku a uvedený rozsah") }
        return v
    }
    public static func isErrorReply(_ reply: String) -> Bool {
        let r = reply.lowercased().trimmingCharacters(in:.whitespacesAndNewlines)
        if r.hasPrefix(">") { return false } // A get value can itself contain words such as "not supported".
        return r.hasPrefix("err") || r.hasPrefix("(err") || r.contains("unknown command") || r.contains("not supported")
    }
}
