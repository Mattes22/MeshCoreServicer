import SwiftUI
import Charts
import MeshCoreKit

enum OperationsTab: String, CaseIterable { case health = "Zdraví", snapshots = "Snímky konfigurace", restart = "Po restartu" }
struct OperationsWorkspace: View {
    @ObservedObject var model: AppModel
    @ObservedObject var operations: OperationsModel
    @State var tab: OperationsTab = .health
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            Picker("Historie správy",selection:$tab) { ForEach(OperationsTab.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(maxWidth:520)
            if let error = operations.storageError { MessageBanner(title:"Lokální historie správy",message:error,symbol:"externaldrive.badge.exclamationmark",color:.orange) }
            switch tab {
            case .health: health
            case .snapshots: SnapshotWorkspace(model:model,operations:operations)
            case .restart: RestartReviewView(model:model,operations:operations)
            }
        }
    }
    private var health: some View {
        VStack(alignment:.leading,spacing:20) {
            Panel(title:"Časově omezené diagnostické měření",symbol:"waveform.path.ecg",subtitle:"Historie a graf jsou místní. Jejich prohlížení nic nevysílá.") {
                HStack {
                    Stepper("Interval: \(DiagnosticPlan.hoursText(model.monitorIntervalMinutes))",value:$model.monitorIntervalMinutes,in:DiagnosticPlan.minimumIntervalMinutes...DiagnosticPlan.maximumIntervalMinutes,step:60)
                    Stepper("Vzorky: \(model.monitorSampleLimit)",value:$model.monitorSampleLimit,in:1...6)
                }.disabled(model.monitoring || model.busy)
                if let plan = model.measurementPlan {
                    Text("Plán: \(plan.samples) požadavky na stav, očekávané \(plan.samples) odpovědi; délka \(DiagnosticPlan.hoursText(plan.durationMinutes)). První vzorek až za \(DiagnosticPlan.hoursText(plan.intervalMinutes)).")
                } else { Text("Upravte plán: interval 3–24 hodin, nejvýše 6 vzorků a celkem nejvýše 24 hodin.").foregroundStyle(.orange) }
                Text(model.measurementRoute == .known ? "Companion má uloženou platnou trasu. Ta nezaručuje doručení ani neměnné podmínky sítě." : "Flood nebo neznámá trasa: požadavek může přeposlat více uzlů. I s hodinovými rozestupy zvažte zatížení sítě.").font(.caption)
                Text("Každý vzorek aktivně vyšle požadavek přes sdílenou LoRa síť a vyvolá odpověď. Výchozí plán: 3 požadavky po 4 h, první za 4 h a poslední za 12 h. Nejde o pasivní příjem. Žádný interval není univerzálně bezpečný. Měření se samo neobnovuje; zpožděné nebo obsazené termíny se přeskočí bez dohánění.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Spustit měření") { model.setMonitoring(true) }.disabled(!model.admin || model.busy || model.monitoring || model.measurementPlan == nil)
                    Button("Zastavit") { model.stopMonitoring() }.disabled(!model.monitoring)
                    Button("Načíst stav jednou") { model.ping() }.disabled(!model.initialized || model.busy || model.selected?.stored != true)
                }
                if let run = model.measurement {
                    ProgressView(value:Double(run.consumed),total:Double(run.plan.samples))
                    Text("\(model.monitoring ? "Probíhá" : "Ukončeno") · termíny \(run.consumed)/\(run.plan.samples) · uloženo \(run.received) · přeskočeno \(run.skipped) · zbývá \(run.remaining)\(run.inFlight ? (run.transmitted ? " · čekám na již odeslaný požadavek" : " · čekám na servisní limit") : "")")
                }
                if let next = model.monitorNext { Text("Další termín \(next.formatted(date:.abbreviated,time:.standard)).").font(.caption) }
                Text("Ruční servis i měření sdílí limit 60 požadavků za hodinu, z toho 12 bez známé trasy. Každý krok dávky se počítá samostatně; mezi kroky je prodleva 15 s, při floodu nebo neznámé trase 60 s.").font(.caption).foregroundStyle(.secondary)
                Text("Zastavení zruší další vzorky. Již odeslaný požadavek nelze vzít zpět; jeho časově omezené čekání se dokončí. Po odpojení, spánku, změně uzlu, ztrátě oprávnění nebo chybě je nutné nové výslovné spuštění.").font(.caption).foregroundStyle(.secondary)
            }
            Panel(title:"Napětí baterie v čase",symbol:"battery.75percent",subtitle:"Napětí bez odhadu procent a chemie baterie. Snímek odpovědi vzdáleného repeateru.") {
                if operations.current.samples.isEmpty { Text("Zatím nejsou uložené vzorky. Použijte Načíst nyní.").foregroundStyle(.secondary) }
                else {
                    Chart(operations.current.samples) { sample in
                        LineMark(x:.value("Čas",sample.date),y:.value("Napětí · V",Double(sample.battery)/1000)).foregroundStyle(MeshTheme.accent)
                        PointMark(x:.value("Čas",sample.date),y:.value("Napětí · V",Double(sample.battery)/1000)).foregroundStyle(MeshTheme.accent).symbolSize(12)
                    }.chartYScale(domain:.automatic(includesZero:false)).frame(height:180)
                    if let last = operations.current.samples.last { Text(String(format:"Poslední vzorek %.3f V · %@",Double(last.battery)/1000,last.date.formatted(date:.abbreviated,time:.standard))).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Panel(title:"Doba běhu a provoz",symbol:"chart.xyaxis.line",subtitle:"Pokles uptime označuje možný restart. Čítače paketů jsou kumulativní od restartu a nejsou rychlost přenosu.") {
                if !operations.current.samples.isEmpty {
                    Chart(operations.current.samples) { sample in LineMark(x:.value("Čas",sample.date),y:.value("Uptime · h",Double(sample.uptime)/3600)).foregroundStyle(.blue) }.frame(height:150)
                }
                ForEach(Array(operations.current.samples.suffix(12).reversed())) { sample in
                    HStack(alignment:.top) {
                        Text(sample.date.formatted(date:.abbreviated,time:.standard)).font(.caption)
                        Spacer(); Text("\(MeshPresentation.duration(sample.uptime)) · RX \(sample.received) · TX \(sample.sent)").font(.caption.monospacedDigit())
                    }
                    Text(String(format:"Poslední paket na repeateru: RSSI %d dBm · SNR %.2f dB · šum %d dBm",sample.rssi,sample.snr,sample.noise)).font(.caption2).foregroundStyle(.secondary)
                }
                Text("Odesílatel posledního paketu není známý; RSSI/SNR není měření celého spoje s companionem. Uchovává se posledních 2 000 vzorků pro uzel.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
struct SnapshotWorkspace: View {
    @ObservedObject var model: AppModel
    @ObservedObject var operations: OperationsModel
    @State private var label = ""
    @State private var chosen: UUID?
    @State private var selectedKeys: Set<String> = []
    init(model: AppModel, operations: OperationsModel) {
        self.model = model; self.operations = operations; _chosen = State(initialValue:operations.current.snapshots.last?.id)
    }
    private var snapshot: ConfigSnapshot? { operations.current.snapshots.first{$0.id == chosen} }
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            Panel(title:"Snímky načtené konfigurace",symbol:"square.stack.3d.up",subtitle:"Pouze podporované hodnoty ze skutečného čtení; hesla ani soukromé klíče nejsou součástí snímku. Snímek může obsahovat veřejný kontakt vlastníka.") {
                HStack { TextField("Název snímku · volitelné",text:$label).textFieldStyle(.roundedBorder); Button("Uložit načtené hodnoty") { model.captureSnapshot(name:label) }.disabled(model.busy || model.config.isEmpty || model.selfInfo == nil) }
                HStack { Button("Načíst konfiguraci z repeateru") { model.readConfig() }.disabled(!model.admin || model.busy); Spacer(); Button("Importovat JSON…") { model.importSnapshot() }.disabled(model.busy || operations.document == nil) }
                Text("Uložení nečte nové hodnoty po LoRa. Ve snímku budou jen dosud načtená pole s časem jejich čtení. Neověřené zápisy se vynechají. Uchovává se nejvýše 30 snímků na repeater.").font(.caption).foregroundStyle(.secondary)
                Picker("Snímek",selection:$chosen) {
                    Text("Vyberte snímek…").tag(Optional<UUID>.none)
                    ForEach(operations.current.snapshots.reversed()) { s in Text("\(s.name) · \(s.date.formatted(date:.abbreviated,time:.shortened))").tag(Optional(s.id)) }
                }
            }
            if let snapshot {
                Panel(title:"Vybrat hodnoty k porovnání",symbol:"arrow.left.arrow.right",subtitle:"Rádio je ve výchozím výběru vypnuté. Snímek lze obnovit jen na stejný repeater a se stejnou identitou companionu.") {
                    ForEach(CLIValidation.keys.filter{snapshot.values[$0] != nil},id:\.self) { key in
                        HStack(alignment:.top) {
                            Toggle(key,isOn:Binding(get:{selectedKeys.contains(key)},set:{ if $0 { selectedKeys.insert(key) } else { selectedKeys.remove(key) }; model.restorePreview = nil })).font(.system(.callout,design:.monospaced)).frame(minWidth:190,alignment:.leading)
                            Text(snapshot.values[key]!).font(.callout).textSelection(.enabled)
                            Spacer()
                            Text(snapshot.readAt?[key].map{"Čteno \($0.formatted(date:.abbreviated,time:.shortened))"} ?? "Čas čtení neuveden").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    HStack {
                        Button("Exportovat JSON…") { model.exportSnapshot(snapshot) }
                        Button("Smazat snímek",role:.destructive) { operations.removeSnapshot(snapshot.id); chosen = nil; model.restorePreview = nil }
                        Spacer(); Button("Načíst aktuální stav a porovnat") { model.compareSnapshot(snapshot,keys:selectedKeys) }.buttonStyle(.borderedProminent).disabled(!model.admin || model.busy || selectedKeys.isEmpty)
                    }
                }
            }
            if let preview = model.restorePreview, preview.snapshot.id == chosen {
                Panel(title:"Rozdíly proti aktuálnímu čtení",symbol:"list.bullet.rectangle",subtitle:"Zatím nebyla odeslána žádná změna. Před zápisem se ještě ověří, že se stav od porovnání nezměnil.") {
                    if preview.proposed.isEmpty { Label("Vybrané hodnoty už souhlasí",systemImage:"checkmark.circle").foregroundStyle(.teal) }
                    ForEach(preview.keys,id:\.self) { key in InfoRow(label:key,value:"\(preview.current[key] ?? "—") → \(preview.proposed[key]!)") }
                    HStack { Spacer(); Button("Zkontrolovat a obnovit…") { model.restoreSnapshot() }.buttonStyle(.borderedProminent).disabled(!model.admin || model.busy || preview.proposed.isEmpty) }
                }
            }
        }.onChange(of:chosen,initial:true) { _,_ in selectedKeys = Set(snapshot?.values.keys.filter{$0 != "radio"} ?? []); model.restorePreview = nil }
            .onChange(of:operations.selectedID) { _,_ in chosen = nil; selectedKeys = []; model.restorePreview = nil }
    }
}
struct RestartReviewView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var operations: OperationsModel
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            Panel(title:"Kontrola po restartu",symbol:"arrow.clockwise.circle",subtitle:"Dostupnost, správný čas a provedení změny jsou tři odlišné věci. Žádný kontrolní příkaz se neposílá automaticky.") {
                if let review = operations.current.restart {
                    Text(review.reason).font(.headline)
                    Text(review.date.formatted(date:.abbreviated,time:.standard)).font(.caption).foregroundStyle(.secondary)
                    Label(review.reachable.map{"Odpověď na stav: \($0.formatted(date:.abbreviated,time:.standard))"} ?? "Dostupnost po tomto požadavku zatím nebyla ověřena",systemImage:review.reachable == nil ? "circle" : "checkmark.circle")
                    Label(review.clockChecked.map{"Hodiny odpovídaly času Macu: \($0.formatted(date:.abbreviated,time:.standard))"} ?? "Správný čas po tomto požadavku zatím nebyl ověřen",systemImage:review.clockChecked == nil ? "circle" : "checkmark.circle")
                } else { Text("Není zaznamenaný požadavek na restart ani pokles doby běhu. Hodiny můžete kdykoliv ověřit ručně.").foregroundStyle(.secondary) }
                HStack { Button("Ověřit dostupnost") { model.ping() }.disabled(!model.initialized || model.busy || model.selected?.stored != true); Button("Načíst hodiny") { model.readRepeaterInfo() }.disabled(!model.admin || model.busy); Button("Synchronizovat hodiny…") { model.syncRepeaterClock() }.disabled(!model.admin || model.busy) }
                if let text = model.tools.clock { Text("Poslední načtení hodin: \(text)").font(.caption).textSelection(.enabled) }
            }
            Panel(title:"Změny čekající na ověření",symbol:"exclamationmark.circle",subtitle:"Odeslání nebo odpověď na příkaz nemusí ověřovat výsledný stav. Při nejistotě nejprve čtěte stav, zápis slepě neopakujte.") {
                if model.session.requiresReconnect { Text("Po timeoutu nejprve ručně odpojte a znovu připojte companion, potom se přihlaste. Do té doby se kontrolní čtení neposílá.").font(.caption).foregroundStyle(.orange) }
                if operations.current.unverified.isEmpty { Label("Žádné uložené neověřené změny",systemImage:"checkmark.circle").foregroundStyle(.teal) }
                ForEach(operations.current.unverified) { change in
                    HStack {
                        VStack(alignment:.leading,spacing:4) {
                            Text(change.key).font(.callout.weight(.semibold))
                            Text(change.date.formatted(date:.abbreviated,time:.standard)).font(.caption).foregroundStyle(.secondary)
                            if let expected = change.expected { Text("Zamýšleno: \(expected)").font(.caption).textSelection(.enabled) }
                        }
                        Spacer()
                        let plan = VerificationAction(key:change.key)
                        if plan != .manual {
                            Button(plan.title) { model.verifyChange(change) }.disabled(!model.admin || model.busy || model.session.requiresReconnect)
                        } else { Text(plan.title).font(.caption).foregroundStyle(.secondary) }
                        Button("Označit ručně ověřeno…") {
                            let repeater = operations.selectedID
                            model.confirmation = AppModel.Confirmation(title:"Potvrdit vlastní ověření?",message:"\(change.key)\nTímto pouze odstraníte položku ze seznamu. Aplikace neposílá příkaz a netvrdí, že změnu sama ověřila.",action:{ if let repeater, operations.selectedID == repeater { operations.verifiedChange(change.key,repeater:repeater) } })
                        }
                    }
                }
            }
        }
    }
}
