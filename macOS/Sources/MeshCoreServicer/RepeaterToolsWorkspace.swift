import SwiftUI
import MeshCoreKit

struct CommunitySetupView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            MessageBanner(title:"Prvotní nastavení",message:"Nejdřív načtěte skutečný stav uzlu. Ve výchozím režimu se zachovají jeho hodnoty. Komunitní předvolbu vyberte pouze pro síť, která ji používá; každý zápis vyžaduje kontrolu a potvrzení.",symbol:"checklist",color:.teal)
            Picker("Profil nastavení",selection:Binding(get:{model.tools.useCzechProfile},set:{model.chooseSetupProfile(czech:$0)})) {
                Text("Zachovat nastavení uzlu").tag(false)
                Text("Česká komunita · volitelná předvolba").tag(true)
            }.disabled(model.busy)
            if model.tools.useCzechProfile {
                Text("Flood 25 h · zero-hop vypnutý · duty cycle 10 % / af 9 · dvoubajtové hashe. Před použitím ověřte aktuální doporučení své komunity.").font(.caption).foregroundStyle(.secondary)
            }
            Panel(title:"1 · Načíst současné nastavení",symbol:"arrow.down.circle",subtitle:"Pouze čtení po LoRa; žádná hodnota se tím nezapisuje.") {
                HStack {
                    VStack(alignment:.leading,spacing:4) {
                        Text(model.tools.firmware ?? "Verze repeateru dosud nebyla načtena").font(.callout).textSelection(.enabled)
                        Text("Když firmware výslovně nepodporuje dutycycle, průvodce zkusí ekvivalent af. Při timeoutu se zastaví.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(model.tools.communityLoaded ? "Načíst znovu…" : "Načíst stav repeateru") { model.loadCommunitySetup() }.buttonStyle(.borderedProminent).disabled(!model.admin || model.busy)
                }
            }
            Panel(title:"2 · Zkontrolovat navržené hodnoty",symbol:"list.bullet.rectangle",subtitle:"Zaškrtnuté kroky se provedou až po závěrečném potvrzení. Hodnoty, které už souhlasí, se nepřepisují.") {
                HStack {
                    VStack(alignment:.leading,spacing:4) { Text("Veřejný kontakt vlastníka").font(.callout.weight(.medium)); Text("Jméno a e-mail nebo jiný kontakt · nejvýše 118 UTF-8 bajtů").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    TextField("Jméno / kontakt vlastníka",text:$model.tools.communityOwner).textFieldStyle(.roundedBorder).frame(minWidth:260)
                }.disabled(model.busy)
                Text("Údaj bude veřejně dostupný. Doplňte vlastní kontakt. Znak | firmware používá jako nový řádek.").font(.caption).foregroundStyle(.secondary)
                Divider()
                if model.tools.communityLoaded {
                    ForEach(model.communitySettings) { setting in
                        let current = model.tools.communitySnapshot[setting.key]
                        let same = current.map { MeshPresentation.sameValue(key:setting.key,$0,setting.target) } ?? false
                        HStack(alignment:.top,spacing:12) {
                            Toggle("",isOn:Binding(get:{ model.tools.communitySelected.contains(setting.key) },set:{ if $0 { model.tools.communitySelected.insert(setting.key) } else { model.tools.communitySelected.remove(setting.key) } })).labelsHidden().disabled(current == nil || model.busy || same)
                            VStack(alignment:.leading,spacing:4) {
                                Text(setting.title).font(.callout.weight(.medium))
                                Text(current.map { "Načteno: \($0.isEmpty ? "prázdné" : $0)  →  Návrh: \(setting.target.isEmpty ? "doplňte kontakt" : setting.target)" } ?? "Firmware hodnotu nepodporuje / nedostupná").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                if let message = model.fieldErrors[setting.key] { Text(message).font(.caption).foregroundStyle(.orange) }
                            }
                            Spacer()
                            if same { Label("Souhlasí",systemImage:"checkmark.circle").font(.caption).foregroundStyle(.teal) }
                            else if let state = model.fieldStates[setting.key], [.sending,.verifying,.failed,.uncertain,.different].contains(state) { FieldStatus(model:model,key:setting.key) }
                            else { Text(current == nil ? "Nedostupné" : (model.tools.communitySelected.contains(setting.key) ? "Připraveno" : "Vynecháno")).font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical,6)
                    }
                    if model.tools.communityDutyKey == nil { Label("Duty cycle ani af nebyly potvrzeny jako podporované. Tento krok nebude odeslán.",systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                } else { Text("Doporučení se porovná až se skutečnou odpovědí vybraného repeateru.").foregroundStyle(.secondary).padding(.vertical,8) }
                Divider()
                Toggle("Synchronizovat hodiny podle aktuálního času Macu",isOn:$model.tools.communitySyncClock).disabled(model.busy)
                Text("Hodiny po restartu znovu zkontrolujte a případně synchronizujte. Firmware odmítne posun zpět; nepoužíváme automatický restart ani reset hodin.").font(.caption).foregroundStyle(.secondary)
                if let result = model.tools.clockResult { Text(result).font(.caption).textSelection(.enabled) }
            }
            HStack {
                Text("Rádio, výkon, přeposílání, hesla a identita zůstávají mimo tento profil.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("3 · Zkontrolovat a použít…") { model.applyCommunitySetup() }.buttonStyle(.borderedProminent).disabled(!model.admin || model.busy || !model.tools.communityLoaded)
            }
        }
    }
}

enum RepeaterToolSection: String, CaseIterable { case diagnostics = "Diagnostika", network = "Síť a regiony", access = "Přístup" }
struct RepeaterToolsView: View {
    @ObservedObject var model: AppModel
    @State var section: RepeaterToolSection = .diagnostics
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            Picker("Skupina nástrojů",selection:$section) { ForEach(RepeaterToolSection.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(maxWidth:480)
            switch section {
            case .diagnostics: diagnostics
            case .network: network
            case .access: RepeaterAccessView(model:model)
            }
        }
    }
    private var diagnostics: some View {
        VStack(alignment:.leading,spacing:20) {
            Panel(title:"Verze a hodiny",symbol:"clock",subtitle:"Čas repeateru se vrací v UTC, bez ohledu na časové pásmo Macu.") {
                InfoRow(label:"Firmware repeateru",value:model.tools.firmware ?? "Nenačteno")
                InfoRow(label:"Hardware",value:model.tools.board ?? "Nenačteno")
                InfoRow(label:"Hodiny repeateru · UTC",value:model.tools.clock ?? "Nenačteno")
                if let date = model.tools.clockRead { Text("Načteno \(date.formatted(date:.abbreviated,time:.standard)) · snímek, nikoliv živé hodiny").font(.caption).foregroundStyle(.secondary) }
                HStack { Button("Načíst verzi a čas") { model.readRepeaterInfo() }; Spacer(); Button("Synchronizovat hodiny…") { model.syncRepeaterClock() } }.disabled(!model.admin || model.busy)
                if let result = model.tools.clockResult { Text(result).font(.caption).textSelection(.enabled) }
            }
            Panel(title:"Telemetrie repeateru",symbol:"chart.bar.xaxis",subtitle:"Pouze senzory, které firmware skutečně vrátí. Dostupnost závisí na desce a sestavení firmwaru.") {
                HStack { snapshot(model.tools.telemetryDate); Spacer(); Button("Načíst telemetrii") { model.readTelemetry() }.disabled(!model.admin || model.busy) }
                if let report = model.tools.telemetry {
                    if report.values.isEmpty { Text("Repeater nevrátil dekódovatelné hodnoty.").foregroundStyle(.secondary) }
                    ForEach(report.values) { value in InfoRow(label:"\(value.title) · kanál \(value.channel)",value:value.value) }
                    if let type = report.unsupportedType { Label("Neznámý typ LPP \(type). Další pole se nedekódují odhadem.",systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                }
            }
            Panel(title:"Sousedé bez přeskoku",symbol:"point.3.connected.trianglepath.dotted",subtitle:"Sousedé slyšení rádiem vzdáleného repeateru. Uložený záznam není potvrzení aktuální dostupnosti.") {
                HStack { snapshot(model.tools.neighbourDate); Spacer(); Button("Načíst sousedy") { model.readNeighbours() }.disabled(!model.admin || model.busy) }
                if model.tools.neighbourDate != nil || !model.tools.neighbours.isEmpty {
                    Text("Načteno \(model.tools.neighbours.count) · poslední hlášený celkový počet \(model.tools.neighbourTotal). Seznam se může během stránkování měnit.").font(.caption).foregroundStyle(.secondary)
                    ForEach(model.tools.neighbours) { neighbour in
                        VStack(alignment:.leading,spacing:4) {
                            Text(model.contacts.first(where:{$0.key == neighbour.key})?.name ?? "Neznámý soused").font(.callout.weight(.medium))
                            KeyLabel(key:neighbour.id)
                            Text(String(format:"Slyšen před %@ · SNR posledního paketu tohoto souseda na repeateru %.2f dB",MeshPresentation.duration(neighbour.heardSecondsAgo),neighbour.snr)).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical,5)
                    }
                    if model.tools.neighbours.isEmpty { Text("Seznam sousedů je prázdný.").foregroundStyle(.secondary) }
                }
                Divider()
                Button("Spustit discovery sousedů po LoRa") { model.sendCLI("discover.neighbors") }.disabled(!model.admin || model.busy)
                Text("Discovery aktivně vysílá. Seznam potom načtěte znovu; dokončení CLI není zárukou odpovědí sousedů.").font(.caption).foregroundStyle(.secondary)
            }
            Panel(title:"Vysílání a restart",symbol:"antenna.radiowaves.left.and.right") {
                HStack { Button("Odeslat flood advert") { model.sendCLI("advert") }; Button("Odeslat zero-hop advert") { model.sendCLI("advert.zerohop") }; Spacer(); Button("Restartovat…",role:.destructive) { model.sendCLI("reboot") } }.disabled(!model.admin || model.busy)
                Text("Vysílání je ruční. Restart nemá odpověď potvrzující provedení. Poté zkontrolujte hodiny repeateru.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var network: some View {
        VStack(alignment:.leading,spacing:20) {
            Panel(title:"Síťová nastavení",symbol:"network",subtitle:"Každá hodnota se nejprve načítá. Duty cycle a af jsou dva zápisy stejného omezení, zvolte jeden.") {
                HStack { Text("Rozšířené směrování").font(.callout); Spacer(); Button("Načíst síťové hodnoty") { model.readConfig(keys:CLIValidation.networkKeys) }.disabled(!model.admin || model.busy) }
                SettingEditor(model:model,key:"dutycycle",title:"Duty cycle",hint:"1–100 % · komunitní profil 10 %")
                Divider(); SettingEditor(model:model,key:"af",title:"Airtime factor",hint:"0–9 · af 9 odpovídá duty cycle 10 %")
                Divider(); SettingEditor(model:model,key:"path.hash.mode",title:"Velikost hashe cesty",hint:"0 = 1 B, 1 = 2 B, 2 = 3 B")
                Divider(); SettingEditor(model:model,key:"flood.max",title:"Flood limit",hint:"0–64 hopů")
                Divider(); SettingEditor(model:model,key:"flood.max.advert",title:"Flood limit advertů",hint:"0–64 hopů")
                Divider(); SettingEditor(model:model,key:"flood.max.unscoped",title:"Flood bez regionu",hint:"0–64 hopů")
                Divider(); SettingEditor(model:model,key:"loop.detect",title:"Detekce smyček",hint:"off, minimal, moderate, strict")
            }
            RegionEditor(model:model)
            Panel(title:"Identitní klíč",symbol:"key",subtitle:"Identita určuje adresu uzlu a vazbu uložených kontaktů.") {
                Text("Tato verze identitu nezmění ani negeneruje soukromý klíč. Změna vyžaduje samostatný ověřený postup a může přerušit správu repeateru. Veřejný klíč vybraného uzlu je zobrazený nahoře.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
    private func snapshot(_ date: Date?) -> some View { Text(date.map { "Načteno \($0.formatted(date:.abbreviated,time:.standard))" } ?? "Dosud nenačteno").font(.caption).foregroundStyle(.secondary) }
}

struct RegionEditor: View {
    @ObservedObject var model: AppModel
    @State private var operation = "put"
    @State private var name = ""
    @State private var parent = ""
    var body: some View {
        Panel(title:"Regiony přeposílání",symbol:"arrow.triangle.branch",subtitle:"Čtení a změny regionů přes vzdálené CLI. Souhrn může firmware zkrátit na 160 znaků.") {
            HStack { Text("Konfigurace regionů").font(.callout); Spacer(); Button("Načíst regiony") { model.readRegions() }.disabled(!model.admin || model.busy) }
            ForEach([model.tools.regionDump,model.tools.regionHome,model.tools.regionDefault].compactMap{$0},id:\.self) { Text($0).font(.system(.callout,design:.monospaced)).textSelection(.enabled) }
            Divider()
            HStack {
                Picker("Operace",selection:$operation) {
                    Text("Přidat / upravit").tag("put"); Text("Povolit flood").tag("allowf"); Text("Zakázat flood").tag("denyf"); Text("Domácí region").tag("home"); Text("Výchozí scope").tag("default"); Text("Odstranit").tag("remove")
                }.frame(width:220)
                TextField("Úplný název regionu",text:$name).textFieldStyle(.roundedBorder)
                if operation == "put" { TextField("Rodič · prázdné = *",text:$parent).textFieldStyle(.roundedBorder) }
            }.disabled(!model.admin || model.busy)
            HStack {
                Text("Před změnou načtěte a zkontrolujte přehled. Operace může omezit přeposílání; následuje potvrzení, region save a nové čtení.").font(.caption).foregroundStyle(.secondary)
                Spacer(); Button("Zkontrolovat změnu…") { model.changeRegion(operation:operation,name:name,parent:parent) }.disabled(!model.admin || model.busy || name.isEmpty || model.tools.regionDump == nil)
            }
            if let result = model.tools.regionResult { Text(result).font(.caption).textSelection(.enabled) }
        }.onChange(of:model.selectedID) { _,_ in name = ""; parent = "" }
    }
}

struct RepeaterAccessView: View {
    @ObservedObject var model: AppModel
    @State private var publicKey = ""
    @State private var permissions: UInt8 = 3
    @State private var newPassword = ""
    @State private var repeatedPassword = ""
    @State private var guest = false
    @State private var remember = true
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            Panel(title:"Řízení přístupu · ACL",symbol:"person.badge.shield.checkmark",subtitle:"Seznam vrací šestibajtové prefixy klíčů a může být omezen velikostí jediné odpovědi. Není zaručený úplný seznam.") {
                HStack { Text(model.tools.accessDate.map { "Načteno \($0.formatted(date:.omitted,time:.standard))" } ?? "Dosud nenačteno").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Načíst oprávnění") { model.readAccess() }.disabled(!model.admin || model.busy) }
                ForEach(model.tools.access) { entry in
                    HStack {
                        Text(entry.id).font(.system(.callout,design:.monospaced)).textSelection(.enabled)
                        Text(contactName(entry.prefix)).foregroundStyle(.secondary)
                        Spacer(); Text(entry.role).font(.callout); Text(String(format:"0x%02X",entry.permissions)).font(.caption.monospaced())
                    }
                }
                if model.tools.accessDate != nil && model.tools.access.isEmpty { Text("V odpovědi nejsou žádné uložené položky ACL.").foregroundStyle(.secondary) }
                Divider()
                HStack {
                    TextField("Celý veřejný klíč · 64 hex znaků",text:$publicKey).textFieldStyle(.roundedBorder)
                    Menu("Z kontaktů") { ForEach(model.contacts.filter{$0.kind == 1 && $0.stored}) { c in Button(c.name) { publicKey = c.id } } }
                }
                HStack {
                    Picker("Oprávnění",selection:$permissions) { Text("Správce · 3").tag(UInt8(3)); Text("Čtení a zápis · 2").tag(UInt8(2)); Text("Pouze čtení · 1").tag(UInt8(1)); Text("Odebrat · 0").tag(UInt8(0)) }.frame(maxWidth:300)
                    Spacer(); Button("Zkontrolovat změnu ACL…") { model.changeAccess(publicKey:publicKey,permissions:permissions) }.disabled(publicKey.isEmpty)
                }
                Text("Pouze role 3 umožňuje vzdálené CLI repeateru. Vlastnímu companionu zde nelze odebrat správu. Používá se celý klíč; seznam zobrazuje jen prefix.").font(.caption).foregroundStyle(.secondary)
            }.disabled(!model.admin || model.busy)
            Panel(title:"Hesla vzdáleného přístupu",symbol:"lock.shield",subtitle:"Samostatné heslo správce a hosta. Hesla se nečtou do běžného formuláře.") {
                Picker("Změnit",selection:$guest) { Text("Heslo správce").tag(false); Text("Heslo hosta").tag(true) }.pickerStyle(.segmented).frame(maxWidth:360)
                HStack { SecureField("Nové heslo · 1–15 UTF-8 bajtů",text:$newPassword); SecureField("Zopakovat nové heslo",text:$repeatedPassword) }.textFieldStyle(.roundedBorder)
                if !guest { Toggle("Po potvrzení změny uložit nové heslo do Klíčenky macOS",isOn:$remember).font(.caption) }
                HStack {
                    Text("Po změně hesla správce se přihlášení v aplikaci zruší. Nové přihlášení proveďte samostatně. Heslo hosta se lokálně neukládá.").font(.caption).foregroundStyle(.secondary)
                    Spacer(); Button("Změnit heslo…") {
                        let secret = newPassword; newPassword = ""; repeatedPassword = ""
                        model.changeRemotePassword(secret,guest:guest,saveToKeychain:remember)
                    }.disabled(newPassword.isEmpty || newPassword != repeatedPassword || newPassword.utf8.count > 15)
                }
                if let result = model.tools.passwordResult { Text(result).font(.caption).textSelection(.enabled) }
            }.disabled(!model.admin || model.busy)
        }.onChange(of:model.selectedID) { _,_ in publicKey = ""; newPassword = ""; repeatedPassword = "" }
    }
    private func contactName(_ prefix: Data) -> String {
        let matches = model.contacts.filter { $0.key.prefix(6) == prefix }
        return matches.count == 1 ? matches[0].name : (matches.isEmpty ? "Neznámý kontakt" : "Nejednoznačný prefix")
    }
}
