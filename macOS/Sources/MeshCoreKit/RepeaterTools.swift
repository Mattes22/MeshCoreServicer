import Foundation

public struct CommunitySetting: Identifiable, Equatable, Sendable {
    public let key: String
    public let title: String
    public let target: String
    public var id: String { key }
    public init(key: String,title: String,target: String) { self.key = key; self.title = title; self.target = target }
    public static func recommended(dutyKey: String?, owner: String) -> [Self] {
        var result = [Self(key:"flood.advert.interval",title:"Flood advert · hodiny",target:"25"),Self(key:"advert.interval",title:"Zero-hop advert · minuty",target:"0")]
        if let key = dutyKey { result.append(Self(key:key,title:key == "dutycycle" ? "Duty cycle · %" : "Airtime factor",target:key == "dutycycle" ? "10" : "9")) }
        result.append(Self(key:"path.hash.mode",title:"Hash cesty · režim",target:"1"))
        result.append(Self(key:"owner.info",title:"Veřejný kontakt vlastníka",target:owner))
        return result
    }
}
public struct AccessEntry: Identifiable, Equatable, Sendable {
    public let prefix: Data
    public let permissions: UInt8
    public var id: String { prefix.hex }
    public var role: String { [0:"Host / odebráno",1:"Pouze čtení",2:"Čtení a zápis",3:"Správce"][Int(permissions & 3)]! }
    public static func decode(_ data: Data) throws -> [Self] {
        var r = Reader(data), result: [Self] = []
        while r.offset < r.bytes.count {
            if r.bytes[r.offset...].allSatisfy({ $0 == 0 }) {
                guard r.bytes.count-r.offset <= 15 else { throw MeshError.invalid("padding ACL") }; break
            }
            result.append(Self(prefix:try r.data(6),permissions:try r.u8()))
        }
        return result
    }
}
public struct RepeaterNeighbour: Identifiable, Equatable, Sendable {
    public let key: Data
    public let heardSecondsAgo: UInt32
    public let snr: Double
    public var id: String { key.hex }
}
public struct NeighbourPage: Equatable, Sendable {
    public let total: Int
    public let entries: [RepeaterNeighbour]
    public static func request(offset: UInt16, nonce: UInt32) -> Data {
        // Version 0, up to 3 full 32-byte keys, newest first. Max 130 bytes of entries.
        var d = Data([6,0,3,UInt8(truncatingIfNeeded:offset),UInt8(offset >> 8),0,32]); d.appendLE(nonce); return d
    }
    public static func decode(_ data: Data) throws -> Self {
        var r = Reader(data); let total = Int(try r.u16()), count = Int(try r.u16())
        guard count <= 3, count <= total, r.bytes.count-r.offset >= count * 37 else { throw MeshError.invalid("stránka sousedů") }
        var entries: [RepeaterNeighbour] = []
        for _ in 0..<count { entries.append(RepeaterNeighbour(key:try r.data(32),heardSecondsAgo:try r.u32(),snr:Double(try r.i8())/4)) }
        guard r.bytes.count-r.offset <= 15, r.bytes[r.offset...].allSatisfy({$0 == 0}) else { throw MeshError.invalid("padding sousedů") }
        return Self(total:total,entries:entries)
    }
}
public struct TelemetryValue: Identifiable, Equatable, Sendable {
    public let channel: UInt8
    public let type: UInt8
    public let title: String
    public let value: String
    public let position: Int
    public var id: Int { position }
}
public struct TelemetryReport: Equatable, Sendable {
    public let values: [TelemetryValue]
    public let unsupportedType: UInt8?
    public static func decode(_ data: Data) throws -> Self {
        var r = Reader(data), values: [TelemetryValue] = []
        let specs: [UInt8:(Int,Double,Bool,String,String)] = [
            0:(1,1,false,"Digitální vstup",""),1:(1,1,false,"Digitální výstup",""),2:(2,100,true,"Analogový vstup",""),3:(2,100,true,"Analogový výstup",""),
            100:(4,1,false,"Senzor",""),101:(2,1,false,"Osvětlení","lx"),102:(1,1,false,"Přítomnost",""),103:(2,10,true,"Teplota","°C"),104:(1,2,false,"Relativní vlhkost","%"),
            115:(2,10,false,"Tlak","hPa"),116:(2,100,false,"Napětí","V"),117:(2,1000,false,"Proud","A"),118:(4,1,false,"Frekvence","Hz"),120:(1,1,false,"Podíl","%"),121:(2,1,true,"Výška","m"),125:(2,1,false,"Koncentrace","ppm"),128:(2,1,false,"Výkon","W"),130:(4,1000,false,"Vzdálenost","m"),131:(4,1000,false,"Energie","kWh"),132:(2,1,false,"Směr","°"),133:(4,1,false,"Unix čas","s"),142:(1,1,false,"Spínač","")]
        func number(_ bytes: Data, signed: Bool, scale: Double) -> Double {
            let unsigned = bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            let bits = bytes.count*8
            let value = signed && (unsigned & (1 << (bits-1))) != 0 ? Int64(unsigned)-Int64(1 << bits) : Int64(unsigned)
            return Double(value)/scale
        }
        func format(_ n: Double) -> String { String(format:"%g",locale:Locale(identifier:"cs_CZ"),n) }
        while r.offset < r.bytes.count {
            if r.bytes[r.offset...] .allSatisfy({ $0 == 0 }) { break } // AES zero padding / end-of-data
            let channel = try r.u8(), type = try r.u8()
            let title: String, value: String
            if let (size,scale,signed,label,unit) = specs[type] {
                title = label; value = format(number(try r.data(size),signed:signed,scale:scale)) + (unit.isEmpty ? "" : " " + unit)
            } else if [113,134,136,135].contains(type) {
                let size = type == 136 ? 3 : (type == 135 ? 1 : 2)
                let scale: Double = type == 113 ? 1000 : (type == 134 ? 100 : (type == 136 ? 10000 : 1))
                var components: [String] = []
                for axis in 0..<3 { components.append(format(number(try r.data(size),signed:type != 135,scale:type == 136 && axis == 2 ? 100 : scale))) }
                title = [113:"Zrychlení · g",134:"Gyroskop · °/s",136:"Poloha · °, °, m",135:"Barva · RGB"][type]!
                value = components.joined(separator:", ")
            } else { return Self(values:values,unsupportedType:type) }
            values.append(TelemetryValue(channel:channel,type:type,title:title,value:value,position:values.count))
        }
        return Self(values:values,unsupportedType:nil)
    }
}
public enum RepeaterCommand {
    public static func clockDate(_ text: String) -> Date? {
        guard text.range(of:"^\\d{2}:\\d{2} - \\d{1,2}/\\d{1,2}/\\d{4} UTC$",options:.regularExpression) != nil else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier:"en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT:0)
        formatter.dateFormat = "HH:mm - d/M/yyyy 'UTC'"; formatter.isLenient = false
        return formatter.date(from:text)
    }
    public static func password(_ value: String) throws -> String {
        guard (1...15).contains(value.utf8.count), !value.contains(where:{$0.isWhitespace || $0.isNewline}), !value.utf8.contains(0) else { throw MeshError.invalid("heslo musí mít 1–15 UTF-8 bajtů bez mezer a NUL") }; return value
    }
    public static func publicKey(_ value: String) throws -> String {
        let key = value.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        guard key.utf8.count == 64, key.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw MeshError.invalid("úplný veřejný klíč musí mít 64 hexadecimálních znaků") }; return key
    }
    public static func regionName(_ value: String, allowWildcard: Bool = false) throws -> String {
        if allowWildcard && value == "*" { return value }
        // Conservative CLI token: preserve complete names and avoid prefix or delimiter injection.
        guard !value.isEmpty, value.utf8.count <= 30, value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [35,45,46,95].contains($0) }) else { throw MeshError.invalid("název regionu: 1–30 znaků A–Z, a–z, 0–9, #, -, . nebo _") }; return value
    }
}
