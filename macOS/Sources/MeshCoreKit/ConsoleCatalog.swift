import Foundation

/// Remote CLI subset verified in CommonCLI.cpp / CommonRadioPrefs.cpp at this commit.
/// A catalogue entry describes syntax; it is not a capability advertised by a device.
public enum ConsoleCatalog {
    public static let firmwareCommit = "81dbae592ffad40b4212bc0b37e82b38da08f4bc"
    public struct Entry: Identifiable, Equatable, Sendable {
        public let command: String
        public let arguments: String
        public let title: String
        public let detail: String
        public let changesState: Bool
        public var id: String { command }
        public var syntax: String { command + (arguments.isEmpty ? "" : " " + arguments) }
        public var insertion: String { command + (arguments.isEmpty ? "" : " ") }
    }
    public struct Suggestion: Identifiable, Equatable, Sendable {
        public let insertion: String
        public let entry: Entry?
        public let fromHistory: Bool
        public var id: String { insertion }
    }
    private static let fields: [(String,String,String,String)] = [
        ("name","Název uzlu","<název>","Nejvýše 23 UTF-8 bajtů, bez znaku |."),
        ("lat","Zeměpisná šířka","<stupně>","−90 až 90, desetinná tečka."),
        ("lon","Zeměpisná délka","<stupně>","−180 až 180, desetinná tečka."),
        ("tx","Vysílací výkon","<dBm>","Aplikace přijímá 1–22 dBm. Skutečné možnosti závisejí na desce a firmwaru; zohledněte místní pravidla."),
        ("radio","Parametry rádia","<MHz,BW_kHz,SF,CR>","Čtyři hodnoty oddělené čárkou. Uložené rádio se použije po restartu; hrozí ztráta LoRa spojení. Nepředvyplňuje se frekvence sítě."),
        ("advert.interval","Zero-hop advert","<minuty>","0 vypne automatický advert; jinak sudý počet 60–240 minut."),
        ("flood.advert.interval","Flood advert","<hodiny>","0 vypne automatický advert; jinak 3–168 hodin."),
        ("repeat","Přeposílání","<on|off>","Zapnutí nebo vypnutí přeposílání vzdáleného uzlu."),
        ("owner.info","Veřejný kontakt vlastníka","<kontakt>","Nejvýše 118 UTF-8 bajtů. Údaj bude veřejný; | znamená nový řádek."),
        ("dutycycle","Duty cycle","<procenta>","1–100 %. Dostupné od firmwaru 1.15; af je jiné vyjádření stejného nastavení."),
        ("af","Airtime factor","<faktor>","0–9. Duty cycle = 100 / (af + 1) %. Nezapisujte současně s dutycycle."),
        ("path.hash.mode","Velikost hashe cesty","<0|1|2>","0 = 1 bajt, 1 = 2 bajty, 2 = 3 bajty."),
        ("flood.max","Limit flood přeskoků","<0–64>","Horní hranice počtu přeskoků."),
        ("flood.max.advert","Limit advert přeskoků","<0–64>","Horní hranice přeskoků flood advertu."),
        ("flood.max.unscoped","Limit přeskoků bez regionu","<0–64>","Horní hranice přeskoků neomezeného flood provozu."),
        ("loop.detect","Detekce smyček","<off|minimal|moderate|strict>","Režim detekce smyček při přeposílání.")
    ]
    public static let entries: [Entry] = {
        func read(_ command: String,_ title: String,_ detail: String) -> Entry {
            Entry(command:command,arguments:"",title:title,detail:detail,changesState:false)
        }
        var result = [read("ver","Verze firmwaru","Verze vzdáleného uzlu, nikoliv companionu."),
            read("board","Hardware","Označení desky vzdáleného uzlu."),
            read("clock","Hodiny v UTC","Snímek času repeateru. Tento příkaz čas nemění."),
            read("neighbors","Sousedé repeateru","Seznam uzlů slyšených repeaterem; nejde o sousedy Macu."),
            read("region","Regiony","Přehled regionů a oprávnění flood provozu."),
            read("region home","Domovský region","Pouze čtení domovského regionu."),
            read("region default","Výchozí region","Pouze čtení výchozího rozsahu.")]
        for (key,title,arguments,detail) in fields {
            result.append(read("get " + key,title,"Čtení. " + detail))
            result.append(Entry(command:"set " + key,arguments:arguments,title:title,detail:detail,changesState:true))
        }
        result += [Entry(command:"time",arguments:"<Unix_sekundy>",title:"Nastavit čas",detail:"Unix čas v sekundách UTC. Firmware čas neposouvá zpět. Po restartu hodiny znovu zkontrolujte.",changesState:true),
            Entry(command:"advert",arguments:"",title:"Odeslat flood advert",detail:"Vyvolá rádiové vysílání repeateru.",changesState:true),
            Entry(command:"advert.zerohop",arguments:"",title:"Odeslat zero-hop advert",detail:"Vyvolá rádiové vysílání bez přeskoků.",changesState:true),
            Entry(command:"reboot",arguments:"",title:"Restart repeateru",detail:"Vyžaduje potvrzení. Příkaz nemá vzdálenou odpověď; přijetí companionem nepotvrzuje restart.",changesState:true)]
        return result
    }()
    public static func entry(for input: String) -> Entry? {
        let text = input.trimmingCharacters(in:.whitespaces)
        return entries.sorted { $0.command.count > $1.command.count }.first { text == $0.command || (!$0.arguments.isEmpty && text.hasPrefix($0.command + " ")) }
    }
    public static func suggestions(for input: String, history: [String] = [], includeHistory: Bool = true, includeChanges: Bool = false, limit: Int = 6) -> [Suggestion] {
        guard limit > 0, !CLIValidation.sensitive(input) else { return [] }
        let text = input.trimmingCharacters(in:.whitespaces)
        func folded(_ s: String) -> String { s.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"cs_CZ")) }
        let query = folded(text)
        var results: [Suggestion] = []
        // History supplies arguments only from this process; secrets never enter this catalogue.
        if includeHistory && !query.isEmpty {
            for value in history where !CLIValidation.sensitive(value) && value.utf8.count <= 133 && !value.contains(where: { $0.isNewline || $0 == "\0" }) {
                let entry = entry(for:value)
                guard includeChanges || entry?.changesState == false else { continue }
                if folded(value).hasPrefix(query) && value != text && !results.contains(where:{$0.insertion == value}) {
                    results.append(Suggestion(insertion:value,entry:entry,fromHistory:true))
                }
            }
        }
        if includeChanges {
            // Only firmware-defined enum values; never invent a location, radio or contact.
            let options: [(String,[String])] = [("repeat",["on","off"]),("path.hash.mode",["0","1","2"]),("loop.detect",["off","minimal","moderate","strict"])]
            for (key,values) in options {
                let command = "set " + key
                guard text == command || text.hasPrefix(command + " ") else { continue }
                for value in values {
                    let candidate = command + " " + value
                    if candidate.hasPrefix(text), candidate != text, !results.contains(where:{$0.insertion == candidate}) {
                        results.append(Suggestion(insertion:candidate,entry:entry(for:candidate),fromHistory:false))
                    }
                }
            }
        }
        let matching = entries.filter { entry in
            (includeChanges || !entry.changesState) && entry.command != text && (query.isEmpty || folded(entry.command).contains(query) || folded(entry.title).contains(query))
        }.sorted { a,b in
            let aPrefix = folded(a.command).hasPrefix(query), bPrefix = folded(b.command).hasPrefix(query)
            if aPrefix != bPrefix { return aPrefix }
            return false
        }
        // Preserve deterministic order inside equal rank groups (Swift sort is stable).
        for entry in matching where !results.contains(where:{$0.insertion == entry.insertion}) {
            results.append(Suggestion(insertion:entry.insertion,entry:entry,fromHistory:false))
        }
        return Array(results.prefix(limit))
    }
    /// Validates known templates, while preserving manual access to other firmware commands.
    public static func validate(_ input: String) throws {
        guard !input.isEmpty, input.utf8.count <= 133, !input.contains(where:{ $0.isNewline || $0 == "\0" }) else { throw MeshError.invalid("příkaz musí být jednořádkový a mít nejvýše 133 UTF-8 bajtů") }
        guard let entry = entry(for:input), !entry.arguments.isEmpty else { return }
        let value = String(input.dropFirst(entry.command.count)).trimmingCharacters(in:.whitespaces)
        guard !value.isEmpty, !value.contains("<"), !value.contains(">") else { throw MeshError.invalid("doplňte argument: \(entry.syntax)") }
        if entry.command.hasPrefix("set ") { _ = try CLIValidation.validate(key:String(entry.command.dropFirst(4)),value:value) }
        if entry.command == "time", UInt32(value) == nil { throw MeshError.invalid("čas musí být Unix timestamp v rozsahu UInt32") }
    }
}
