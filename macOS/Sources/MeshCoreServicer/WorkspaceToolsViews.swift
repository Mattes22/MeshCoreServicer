import SwiftUI
import MeshCoreKit

struct CompanionProfilesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: WorkspaceLibrary
    @State private var editing: String?
    @State private var alias = ""
    var body: some View {
        Panel(title:"Profily companionů",symbol:"person.crop.rectangle.stack",subtitle:"Místní názvy a vlastní nastavení konzole, obnovování BLE a intervalu monitoringu. Identita se ověřuje veřejným klíčem.") {
            if let error = library.storageError { Text(error).font(.caption).foregroundStyle(.orange) }
            if library.document.profiles.isEmpty { Text("Profil vznikne po skutečném načtení identity companionu. Žádné zařízení není předvybrané.").font(.callout).foregroundStyle(.secondary) }
            ForEach(library.document.profiles.sorted{$0.lastConnected > $1.lastConnected}) { profile in
                VStack(alignment:.leading,spacing:8) {
                    HStack {
                        VStack(alignment:.leading,spacing:3) {
                            Text(profile.displayName).font(.callout.weight(.semibold))
                            Text("\(library.account == profile.id ? "Aktivní profil" : "Uložený profil") · \(profile.lastConnected.formatted(date:.abbreviated,time:.shortened))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Přejmenovat") { editing = profile.id; alias = profile.alias }
                        Button("Připojit…") { model.connectProfile(profile) }.disabled(model.busy || model.ble.connecting || (model.ble.ready && library.account == profile.id))
                        Button(role:.destructive) {
                            model.confirmation = AppModel.Confirmation(title:"Odstranit místní profil?",message:"Odstraní se jeho místní název, volby, zkratky a evidence testů. Historie zpráv, snímky, hesla v Klíčence ani zařízení se nemažou.",action:{ library.removeProfile(profile.id) })
                        } label: { Image(systemName:"trash") }.disabled(profile.id == library.account || model.busy)
                    }
                    KeyLabel(key:profile.id)
                    if editing == profile.id {
                        HStack {
                            TextField("Vlastní místní název · prázdné obnoví název zařízení",text:$alias).textFieldStyle(.roundedBorder)
                            Button("Uložit") { do { try library.rename(profile.id,alias:alias); editing = nil } catch { model.error = error.localizedDescription } }
                            Button("Zrušit") { editing = nil }
                        }
                    }
                }.padding(.vertical,6)
                Divider()
            }
            Text("Volby měněné při připojení se ukládají do aktivního profilu. Oznámení a soukromí jsou společné pro aplikaci. Přepnutí neobnoví správce, monitoring ani vysílání; kontakty a zprávy se načítají pro novou identitu.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ConsoleShortcutsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: WorkspaceLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var catalog = "get radio"
    @State private var chosen: UUID?
    @State private var argument = ""
    @State private var error: String?
    init(model: AppModel,library: WorkspaceLibrary,selected: UUID? = nil) {
        self.model = model; self.library = library; _chosen = State(initialValue:selected)
    }
    private var shortcut: ConsoleShortcut? { library.shortcuts.first{$0.id == chosen} }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Oblíbené příkazy a šablony").font(.title2.bold())
            Text("Pro aktivní companion. Šablona ukládá název a typ příkazu z katalogu; vlastní hodnotu vyplníte až při použití. Argumenty ani hesla se neukládají.").font(.callout).foregroundStyle(.secondary)
            if let error = error ?? library.storageError { Text(error).font(.caption).foregroundStyle(.orange) }
            List(selection:$chosen) {
                ForEach(library.shortcuts) { item in
                    HStack {
                        Image(systemName:item.template ? "text.badge.plus" : "star")
                        VStack(alignment:.leading) { Text(item.title); Text(ConsoleCatalog.entry(for:item.command)?.syntax ?? item.command).font(.caption.monospaced()).foregroundStyle(.secondary) }
                    }.tag(item.id)
                }
            }.frame(minHeight:140,maxHeight:180)
            if let shortcut, let entry = ConsoleCatalog.entry(for:shortcut.command) {
                Text(entry.detail).font(.caption).foregroundStyle(.secondary)
                if !entry.arguments.isEmpty { TextField("Doplnit \(entry.arguments) · pouze pro toto použití",text:$argument).textFieldStyle(.roundedBorder) }
                HStack {
                    Button("Odstranit zkratku",role:.destructive) { library.removeShortcut(shortcut.id); chosen = nil; argument = "" }
                    Spacer()
                    Button("Vyplnit vstup konzole") {
                        do { model.command = try shortcut.filled(with:argument); dismiss() } catch { self.error = error.localizedDescription }
                    }.buttonStyle(.borderedProminent)
                }
            }
            Divider()
            Text("Nová zkratka").font(.headline)
            TextField("Vlastní název",text:$title).textFieldStyle(.roundedBorder)
            Picker("Příkaz",selection:$catalog) { ForEach(ConsoleCatalog.entries) { entry in Text(entry.syntax).tag(entry.command) } }
            HStack {
                Button("Uložit zkratku") {
                    do {
                        guard !model.knownSecrets.contains(where:{!$0.isEmpty && title.contains($0)}), !CLIValidation.sensitive(title) else { throw MeshError.invalid("název zkratky nesmí obsahovat heslo ani citlivý údaj") }
                        try library.saveShortcut(title:title,command:catalog,template:!(ConsoleCatalog.entry(for:catalog)?.arguments.isEmpty ?? true)); title = ""; error = nil
                    } catch { self.error = error.localizedDescription }
                }.disabled(library.account == nil || title.isEmpty)
                Spacer(); Button("Zavřít") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width:620,height:620,alignment:.topLeading).background(MeshTheme.canvas).tint(MeshTheme.accent)
            .onAppear { catalog = ConsoleCatalog.entry(for:model.command)?.command ?? "get radio" }
            .onChange(of:chosen) { _,_ in argument = ""; error = nil }
            .onChange(of:library.account) { _,_ in dismiss() }
    }
}

struct CommandEvidenceLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: WorkspaceLibrary
    let command: String
    var body: some View {
        if let e = model.evidence(for:command) {
            Label(text(e),systemImage:e.result == .answered ? "checkmark.circle" : "exclamationmark.circle")
                .font(.caption2).foregroundStyle(e.result == .answered ? .teal : .orange)
                .help("Pouze tento uzel a načtená verze firmwaru. Bez známé verze platí jen v této BLE relaci. Odpověď na zápis nepotvrzuje výslednou konfiguraci.")
        } else { Label("Pouze katalog · na tomto uzlu neověřeno",systemImage:"book.closed").font(.caption2).foregroundStyle(.secondary) }
    }
    private func text(_ e: CommandEvidence) -> String {
        let state: String
        switch e.result { case .answered: state = "Odpověď ověřena"; case .unsupported: state = "Uzel příkaz nepodporuje"; case .rejected: state = "Příkaz vrátil chybu" }
        return state + " · " + e.date.formatted(date:.abbreviated,time:.shortened)
    }
}

enum DiagnosticsSheet: String, Identifiable { case report, hardware; var id: String { rawValue } }
struct DiagnosticReportView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot = DiagnosticReportInput()
    @State private var created = Date()
    @State private var includeEvents = true
    private var text: String { DiagnosticReport.render(snapshot,includeEvents:includeEvents,date:created) }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Náhled diagnostického reportu").font(.title2.bold())
            Text("Exportuje se přesně tento náhled. Záznamy relace obsahují jen kategorie událostí. Názvy, identity, text zpráv, CLI, původní log a soukromé údaje jsou vynechané.").font(.callout).foregroundStyle(.secondary)
            HStack { Toggle("Zahrnout časový průběh relace",isOn:$includeEvents); Spacer(); Button("Obnovit náhled") { refresh() } }
            ScrollView { Text(text).font(.system(size:11,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(14) }.background(MeshTheme.surface,in:RoundedRectangle(cornerRadius:8))
            HStack { Button("Zavřít") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Uložit tento report…") { model.exportReport(text) }.buttonStyle(.borderedProminent) }
        }.padding(24).frame(width:740,height:650).background(MeshTheme.canvas).tint(MeshTheme.accent).onAppear { refresh() }
    }
    private func refresh() { snapshot = model.reportInput(); created = Date() }
}

struct HardwareVerificationView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: WorkspaceLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var scope: HardwareCheck?
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Ověření fyzické kompatibility").font(.title2.bold())
            Text("Uživatelský záznam ručně provedeného testu. Aplikace žádný test neprovádí ani automaticky neoznačuje za úspěšný. Výsledek platí pouze pro zachycené identity, firmware, verzi aplikace, macOS a architekturu.").font(.callout).foregroundStyle(.secondary)
            if let scope {
                Text("Companion \(scope.companionFirmware) · repeater \(scope.repeaterFirmware)\nAplikace \(scope.appVersion) · macOS \(scope.osVersion) · \(scope.architecture)").font(.caption.monospaced())
                Text("Companion \(scope.account.prefix(12))… / repeater \(scope.repeater.prefix(12))… · záznam pro tuto načtenou kombinaci").font(.caption2).foregroundStyle(.secondary)
                Form {
                    ForEach(HardwareTest.allCases) { test in
                        let saved = library.document.checks.last{$0.sameScope(as:scope) && $0.test == test}
                        VStack(alignment:.leading,spacing:4) {
                            Picker(test.rawValue,selection:Binding(get:{ saved?.outcome ?? .notTested },set:{ outcome in
                                library.recordCheck(HardwareCheck(account:scope.account,repeater:scope.repeater,companionFirmware:scope.companionFirmware,repeaterFirmware:scope.repeaterFirmware,appVersion:scope.appVersion,osVersion:scope.osVersion,architecture:scope.architecture,test:test,outcome:outcome))
                            })) { ForEach(HardwareOutcome.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
                            if let saved { Text("Ručně zaznamenáno \(saved.date.formatted(date:.abbreviated,time:.shortened))").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                }.formStyle(.grouped)
            } else {
                Text("Zatím není načtená úplná kombinace verzí. Připojte companion, vyberte repeater a přihlaste správce. Poté načtěte verzi repeateru. Žádná kombinace není předem označená jako fyzicky ověřená.").foregroundStyle(.secondary)
                Button("Načíst verzi repeateru po LoRa") { model.readRepeaterInfo() }.disabled(!model.admin || model.busy)
                Spacer()
            }
            if model.busy { ProgressView(model.progress).controlSize(.small) }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange) }
            if let error = library.storageError { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack { Text("Po změně verze se starší výsledky nepovažují za nové ověření.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Zavřít") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width:740,height:650).background(MeshTheme.canvas).tint(MeshTheme.accent).onAppear { scope = model.hardwareScope }
            .onChange(of:model.tools.firmware) { _,_ in if scope == nil { scope = model.hardwareScope } }
            .onChange(of:model.deviceInfo) { _,_ in if scope == nil { scope = model.hardwareScope } }
    }
}
