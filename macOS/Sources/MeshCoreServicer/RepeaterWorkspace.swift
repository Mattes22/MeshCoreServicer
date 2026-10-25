import SwiftUI
import MeshCoreKit

struct RepeaterPicker: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Picker("Repeater",selection:Binding(get:{ model.selectedID },set:{ model.selectRepeater($0) })) {
            Text("Vyberte repeater…").tag(Optional<String>.none)
            ForEach(model.contacts.filter { $0.kind == 2 }) { c in Text(c.name + (c.stored ? "" : " · neuložený")).tag(Optional(c.id)) }
        }.disabled(model.busy)
    }
}
enum RepeaterTab: String, CaseIterable { case overview = "Přehled", settings = "Nastavení", radio = "Rádio", tools = "Nástroje", setup = "Prvotní nastavení", history = "Historie a snímky" }
struct RepeaterWorkspace: View {
    @ObservedObject var model: AppModel
    var openContacts: () -> Void
    var openConsole: () -> Void
    @State var tab: RepeaterTab = .overview
    var toolsSection: RepeaterToolSection = .diagnostics
    var operationsTab: OperationsTab = .health
    var body: some View {
        WorkspaceScroll {
            PageHeading(eyebrow:"Vzdálená správa přes LoRa",title:model.selected?.name ?? "Správa repeateru",subtitle:model.selected.map { MeshPresentation.route($0) } ?? "Vyberte uzel, ověřte přístup a načtěte jeho stav.") {
                RepeaterPicker(model:model).labelsHidden().frame(width:210)
            }
            if let c = model.selected {
                HStack(spacing:10) {
                    StatusPill(text:c.stored ? "Uložený kontakt" : "Neuložený uzel",symbol:c.stored ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.plus")
                    StatusPill(text:model.admin ? "Správce ověřen" : "Bez přihlášení",symbol:model.admin ? "lock.open" : "lock",color:model.admin ? .teal : .secondary)
                    Spacer()
                    if let date = model.verified[c.id] { Text("Odpověď \(date.formatted(date:.omitted,time:.standard))").font(.caption).foregroundStyle(.secondary).help("Dostupnost byla ověřena v uvedeném čase.") }
                }
                KeyLabel(key:c.id)
                Picker("Sekce správy",selection:$tab) { ForEach(RepeaterTab.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                if !c.stored {
                    MessageBanner(title:"Kontakt ještě není uložený",message:"Před vzdálenou správou jej výslovně uložte do companionu.",symbol:"person.crop.circle.badge.plus",color:.orange)
                    Button("Uložit kontakt do companionu") { model.storeContact(c) }.disabled(!model.initialized || model.busy)
                }
                if model.restartRequired { MessageBanner(title:"Rádio je uložené · čeká na restart",message:"Nové parametry se použijí po restartu. Před ním ověřte odpovídající rádio companionu.",symbol:"arrow.clockwise.circle",color:.orange) }
                switch tab {
                case .overview: overview(c)
                case .settings: settings
                case .radio: radio
                case .tools:
                    authorizationHint
                    RepeaterToolsView(model:model,section:toolsSection)
                case .history:
                    OperationsWorkspace(model:model,operations:model.operations,tab:operationsTab)
                case .setup:
                    authorizationHint
                    CommunitySetupView(model:model)
                }
            } else {
                ArchivedOperations(model:model,operations:model.operations)
                Panel(title:"Vyberte repeater z kontaktů",symbol:"antenna.radiowaves.left.and.right") {
                    EmptyWorkspace(symbol:"point.3.connected.trianglepath.dotted",title:"Začněte výběrem uzlu",message:"Nejprve připojte companion a načtěte jeho kontakty. Vzdálený repeater se spravuje po LoRa.")
                    Button("Otevřít kontakty",action:openContacts).buttonStyle(.borderedProminent)
                }
            }
        }
        .safeAreaInset(edge:.bottom,spacing:0) {
            if !model.dirtyKeys.isEmpty {
                HStack(spacing:14) {
                    Circle().fill(.orange).frame(width:7,height:7)
                    VStack(alignment:.leading,spacing:3) { Text("\(model.dirtyKeys.count) neuložené hodnoty").font(.callout.weight(.semibold)); Text("Změny se odešlou až po uložení.").font(.caption2).foregroundStyle(.secondary) }
                    Spacer(); Button("Zahodit úpravy") { model.discardEdits() }; Button("Zkontrolovat a uložit") { model.saveChanges() }.buttonStyle(.borderedProminent)
                }.disabled(model.busy).padding(.horizontal,24).padding(.vertical,14).background(.bar).overlay(alignment:.top) { Divider() }
            }
        }
    }
    @ViewBuilder private func overview(_ c: Contact) -> some View {
        if !model.admin { loginPanel }
        RestartSummary(operations:model.operations)
        HStack {
            VStack(alignment:.leading,spacing:4) { Text("Provozní přehled").font(.headline); Text(model.statsDate.map { "Snímek z \($0.formatted(date:.abbreviated,time:.standard))" } ?? "Stav zatím nebyl načtený").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button { model.ping() } label: { Label("Ověřit a načíst stav",systemImage:"arrow.clockwise") }.disabled(!model.initialized || model.busy || !c.stored)
        }
        if let s = model.stats {
            LazyVGrid(columns:MeshTheme.columns,spacing:12) {
                MetricTile(title:"Baterie repeateru",value:String(format:"%.3f V",Double(s.battery)/1000),symbol:"battery.75percent",detail:"Skutečné napětí · bez odhadu procent")
                MetricTile(title:"Doba běhu",value:MeshPresentation.duration(s.uptime),symbol:"clock",detail:"Od posledního restartu")
                MetricTile(title:"Přijaté pakety",value:s.received.formatted(),symbol:"arrow.down.left",detail:"\(s.receivedFlood) flood · \(s.receivedDirect) direct")
                MetricTile(title:"Odeslané pakety",value:s.sent.formatted(),symbol:"arrow.up.right",detail:"\(s.sentFlood) flood · \(s.sentDirect) direct")
            }
            HStack(alignment:.top,spacing:16) {
                Panel(title:"Rádiový příjem repeateru",symbol:"waveform",subtitle:"Poslední paket na rádiu repeateru; odesílatel není známý.") {
                    InfoRow(label:"RSSI posledního paketu",value:"\(s.lastRSSI) dBm")
                    InfoRow(label:"SNR posledního paketu",value:String(format:"%.2f dB",s.lastSNR))
                    Divider(); InfoRow(label:"Noise floor · šum",value:"\(s.noiseFloor) dBm")
                    Text("Tyto metriky neměří celý spoj Mac–repeater.").font(.caption).foregroundStyle(.secondary)
                }
                Panel(title:"Provoz a vysílací čas",symbol:"chart.bar.xaxis") {
                    InfoRow(label:"TX airtime",value:MeshPresentation.duration(s.txAirtime))
                    InfoRow(label:"RX airtime",value:s.rxAirtime.map(MeshPresentation.duration) ?? "Firmware nevrátil")
                    InfoRow(label:"Vysílací fronta",value:"\(s.queue) paketů")
                    InfoRow(label:"Chyby příjmu",value:s.receiveErrors.map(String.init) ?? "Firmware nevrátil")
                    InfoRow(label:"Duplicity direct / flood",value:"\(s.directDuplicates) / \(s.floodDuplicates)")
                    InfoRow(label:"Chybové příznaky",value:String(format:"0x%04X",s.errorEvents))
                }
            }
        } else {
            Panel(title:"Stav na vyžádání",symbol:"gauge.with.dots.needle.50percent") {
                Text("Načtěte baterii, dobu běhu, provozní čítače a rádiové metriky. Žádost odešle companion po LoRa; podle ACL může být nutné přihlášení správce.").font(.callout).foregroundStyle(.secondary)
            }
        }
        Panel(title:"Nástroje repeateru",symbol:"wrench.and.screwdriver") {
            HStack(spacing:12) {
                Button { model.sendCLI("advert") } label: { Label("Odeslat advert",systemImage:"dot.radiowaves.left.and.right") }.disabled(!model.admin || model.busy)
                Button(action:openConsole) { Label("Otevřít konzoli",systemImage:"terminal") }
                Spacer()
                Button("Restartovat…",role:.destructive) { model.sendCLI("reboot") }.disabled(!model.admin || model.busy)
            }
            Text("Vysílání je ruční. Restart vyžaduje potvrzení a firmware na něj neposílá odpověď.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var loginPanel: some View {
        Panel(title:"Přístup správce",symbol:"lock.shield",subtitle:"Přihlášení k vybranému repeateru přes companion a LoRa.") {
            HStack(spacing:10) {
                SecureField("Heslo správce",text:$model.password).textFieldStyle(.roundedBorder).frame(maxWidth:320).onSubmit { if !model.busy { model.login() } }
                Button("Z Klíčenky") { model.loadPassword() }
                Button("Přihlásit správce") { model.login() }.buttonStyle(.borderedProminent).disabled(!model.initialized || model.selected?.stored != true || model.password.utf8.count > 15)
            }.disabled(model.busy)
            HStack {
                Toggle("Po ověření uložit heslo do Klíčenky macOS",isOn:$model.remember).font(.caption)
                Spacer()
                Menu { Button("Smazat uložené heslo",role:.destructive) { model.forgetPassword() } } label: { Image(systemName:"ellipsis.circle") }.menuStyle(.borderlessButton).frame(width:25)
            }.disabled(model.busy)
            if model.password.utf8.count > 15 { Text("Heslo může mít nejvýše 15 UTF-8 bajtů.").font(.caption).foregroundStyle(.orange) }
        }
    }
    @ViewBuilder private var authorizationHint: some View {
        if !model.admin {
            HStack { Label("Pro změny se nejprve přihlaste jako správce.",systemImage:"lock").font(.callout).foregroundStyle(.secondary); Spacer(); Button("Otevřít přihlášení") { tab = .overview } }
        }
    }
    private var settings: some View {
        VStack(alignment:.leading,spacing:20) {
            authorizationHint
            HStack { Text("Nastavení repeateru").font(.headline); Spacer(); Button { model.readConfig(keys:CLIValidation.basicKeys.filter { $0 != "radio" } + ["owner.info"]) } label: { Label("Načíst nastavení",systemImage:"arrow.clockwise") }.disabled(!model.admin || model.busy) }
            Panel(title:"Identita a poloha",symbol:"mappin.and.ellipse",subtitle:"Hodnoty se načítají z repeateru; nepřebírají se automaticky z kontaktu.") {
                SettingEditor(model:model,key:"name",title:"Název",hint:"Nejvýše 23 UTF-8 bajtů")
                Divider()
                SettingEditor(model:model,key:"lat",title:"Zeměpisná šířka",hint:"−90 až 90 · desetinná tečka")
                Divider()
                SettingEditor(model:model,key:"lon",title:"Zeměpisná délka",hint:"−180 až 180 · desetinná tečka")
            }
            Panel(title:"Přeposílání paketů",symbol:"arrow.triangle.branch",subtitle:"Změna se odešle až po stisknutí Uložit.") {
                SettingEditor(model:model,key:"repeat",title:"Funkce repeateru",hint:"Zapnout nebo vypnout přeposílání")
            }
            Panel(title:"Informace o vlastníkovi",symbol:"person.crop.rectangle",subtitle:"Veřejné kontaktní údaje správce. Znak | firmware převádí na nový řádek.") {
                SettingEditor(model:model,key:"owner.info",title:"Veřejný kontakt",hint:"Nejvýše 118 UTF-8 bajtů")
            }
            Panel(title:"Intervaly advertů",symbol:"dot.radiowaves.left.and.right",subtitle:"Hodnota 0 vypíná periodický advert. Přeposílání se nastavuje samostatně.") {
                SettingEditor(model:model,key:"advert.interval",title:"Zero-hop advert",hint:"0 nebo sudé 60–240 minut")
                Divider()
                SettingEditor(model:model,key:"flood.advert.interval",title:"Flood advert",hint:"0 nebo 3–168 hodin")
            }
        }
    }
    private var radio: some View {
        VStack(alignment:.leading,spacing:20) {
            authorizationHint
            MessageBanner(title:"Změna rádia může přerušit LoRa spojení",message:"Uložené parametry se použijí po restartu. Před změnou ověřte nastavení companionu a repeateru.",symbol:"exclamationmark.triangle.fill",color:.orange)
            RadioEditor(model:model)
            Panel(title:"Výkon vysílače",symbol:"bolt.horizontal",subtitle:"Výkon samotného LoRa čipu; případný externí zesilovač se do něj nezapočítává.") {
                SettingEditor(model:model,key:"tx",title:"Výkon LoRa",hint:"1 až 22 dBm")
            }
            if let s = model.selfInfo {
                Panel(title:"Pro porovnání: rádio companionu",symbol:"cpu",subtitle:"Pouze čtení · tato stránka upravuje vzdálený repeater.") {
                    Text(String(format:"%.3f MHz  ·  %g kHz  ·  SF%d  ·  4/%d",s.frequency,s.bandwidth,s.sf,s.cr)).font(.system(.body,design:.monospaced)).textSelection(.enabled)
                }
            }
        }
    }
}

struct SettingEditor: View {
    @ObservedObject var model: AppModel
    let key: String
    var title: String
    var hint: String
    private var draft: Binding<String> { Binding(get:{ model.edits[key] ?? "" },set:{ model.edits[key] = $0 }) }
    private var validation: String? {
        guard model.isDirty(key) else { return nil }
        do { _ = try CLIValidation.validate(key:key,value:draft.wrappedValue); return nil } catch { return error.localizedDescription }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:9) {
            HStack(alignment:.center,spacing:16) {
                VStack(alignment:.leading,spacing:4) { Text(title).font(.callout.weight(.medium)); Text(hint).font(.caption).foregroundStyle(.secondary) }.frame(minWidth:150,maxWidth:.infinity,alignment:.leading)
                Group {
                    if key == "repeat" {
                        Picker(title,selection:draft) { Text("Nenačteno").tag(""); Text("Zapnuto").tag("on"); Text("Vypnuto").tag("off") }.labelsHidden()
                    } else { TextField("Načtěte hodnotu…",text:draft).textFieldStyle(.roundedBorder) }
                }.frame(width:220).disabled(!model.admin || model.busy || model.config[key] == nil)
                Button { model.readConfig(keys:[key]) } label: { Image(systemName:"arrow.clockwise") }.help("Načíst \(title.lowercased()) z repeateru").disabled(!model.admin || model.busy)
                Button("Uložit") { model.save(key) }.disabled(!model.admin || model.busy || !model.isDirty(key) || validation != nil)
            }
            HStack(alignment:.top) {
                Text(model.config[key].map { "Načteno: \($0)" } ?? "Dosud nenačteno").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Spacer(); FieldStatus(model:model,key:key)
            }
            if let message = validation ?? model.fieldErrors[key] { Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true) }
        }
    }
}
struct FieldStatus: View {
    @ObservedObject var model: AppModel
    let key: String
    @ViewBuilder var body: some View {
        switch model.fieldStates[key] {
        case .reading: status("Načítám…",symbol:"arrow.down",color:.secondary)
        case .sending: status("Odesílám…",symbol:"arrow.up",color:.secondary)
        case .verifying: status("Ověřuji čtením…",symbol:"arrow.clockwise",color:.teal)
        case .failed: status("Operace selhala",symbol:"exclamationmark.circle",color:.orange)
        case .uncertain: status("Změna potvrzena · čtení selhalo",symbol:"exclamationmark.triangle",color:.orange)
        case .unsupported: status("Firmware nepodporuje",symbol:"minus.circle",color:.secondary)
        case .different: status("Vrácena jiná hodnota",symbol:"exclamationmark.triangle",color:.orange)
        default:
            if model.isDirty(key) { status("Neuložená změna",symbol:"circle.fill",color:.orange) }
            else if let date = model.configDates[key] { status("Ověřeno \(date.formatted(date:.omitted,time:.shortened))",symbol:"checkmark.circle",color:.teal) }
        }
    }
    private func status(_ text: String,symbol: String,color: Color) -> some View { Label(text,systemImage:symbol).font(.system(size:10)).foregroundStyle(color) }
}
struct RadioEditor: View {
    @ObservedObject var model: AppModel
    private var raw: String { model.edits["radio"] ?? "" }
    private func part(_ keyPath: WritableKeyPath<RadioDraft,String>) -> Binding<String> {
        Binding(get:{ RadioDraft(raw)[keyPath:keyPath] },set:{ value in var draft = RadioDraft(raw); draft[keyPath:keyPath] = value; model.edits["radio"] = draft.rawValue })
    }
    private var validation: String? {
        guard model.isDirty("radio") else { return nil }
        do { _ = try CLIValidation.validate(key:"radio",value:raw); return nil } catch { return error.localizedDescription }
    }
    var body: some View {
        Panel(title:"Parametry LoRa",symbol:"wave.3.right",subtitle:"Jednotlivá pole sestaví ověřený příkaz set radio.") {
            HStack { Text("Načteno: \(model.config["radio"] ?? "dosud nenačteno")").font(.caption).foregroundStyle(.secondary).textSelection(.enabled); Spacer(); Button { model.readConfig(keys:["radio"]) } label: { Label("Načíst rádio",systemImage:"arrow.clockwise") }.disabled(!model.admin || model.busy) }
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],alignment:.leading,spacing:20) {
                field("Frekvence · MHz") { TextField("MHz · desetinná tečka",text:part(\.frequency)).textFieldStyle(.roundedBorder) }
                field("Šířka pásma · kHz") { valuePicker(part(\.bandwidth),values:["7.8","10.4","15.6","20.8","31.25","41.7","62.5","125","250","500"]) }
                field("Spreading factor") { valuePicker(part(\.spreadingFactor),values:(5...12).map(String.init),prefix:"SF") }
                field("Coding rate") { valuePicker(part(\.codingRate),values:(5...8).map(String.init),prefix:"4/") }
            }.disabled(!model.admin || model.busy || model.config["radio"] == nil)
            Divider()
            HStack { FieldStatus(model:model,key:"radio"); Spacer(); if model.isDirty("radio") { Button("Zahodit úpravu") { model.discardEdits(keys:["radio"]) }.disabled(model.busy) }; Button("Uložit rádio…") { model.save("radio") }.buttonStyle(.borderedProminent).disabled(!model.admin || model.busy || !model.isDirty("radio") || validation != nil) }
            if let error = validation ?? model.fieldErrors["radio"] { Text(error).font(.caption).foregroundStyle(.orange) }
        }
    }
    private func field<V: View>(_ label: String,@ViewBuilder content: () -> V) -> some View { VStack(alignment:.leading,spacing:8) { Text(label).font(.caption).foregroundStyle(.secondary); content() }.frame(maxWidth:.infinity,alignment:.leading) }
    private func valuePicker(_ binding: Binding<String>,values: [String],prefix: String = "") -> some View {
        Picker("Hodnota",selection:binding) {
            Text("Nenačteno").tag("")
            if !binding.wrappedValue.isEmpty && !values.contains(binding.wrappedValue) { Text(prefix + binding.wrappedValue).tag(binding.wrappedValue) }
            ForEach(values,id:\.self) { Text(prefix + $0).tag($0) }
        }.labelsHidden()
    }
}

struct RestartSummary: View {
    @ObservedObject var operations: OperationsModel
    var body: some View {
        if operations.current.restart != nil || !operations.current.unverified.isEmpty {
            MessageBanner(title:"Doporučená kontrola stavu",message:"V historii je restart nebo \(operations.current.unverified.count) neověřených změn. Otevřete Historie a snímky → Po restartu. Dostupnost a hodiny ověřte před opakováním zápisu.",symbol:"checklist",color:.orange)
        }
    }
}

struct ArchivedOperations: View {
    @ObservedObject var model: AppModel
    @ObservedObject var operations: OperationsModel
    var body: some View {
        if let doc = operations.document, !doc.nodes.isEmpty {
            Panel(title:"Lokální historie companionu",symbol:"externaldrive") {
                Picker("Repeater · veřejný klíč",selection:Binding(get:{operations.selectedID},set:{ value in model.selectRepeater(value,then:{operations.select(value)}) })) {
                    Text("Vyberte uloženou historii…").tag(Optional<String>.none)
                    ForEach(doc.nodes.keys.sorted(),id:\.self) { key in Text(key).tag(Optional(key)) }
                }
                .disabled(model.busy)
                Text("Čtení uložených údajů nevysílá. Pro správu připojte companion, načtěte kontakty a vyberte skutečný repeater.").font(.caption).foregroundStyle(.secondary)
            }
            if operations.selectedID != nil { OperationsWorkspace(model:model,operations:operations) }
        }
    }
}
