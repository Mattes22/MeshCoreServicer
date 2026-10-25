import SwiftUI
import MeshCoreKit

struct ConsoleWorkspace: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var preferences: AppPreferences
    var openManagement: () -> Void
    @State private var search = ""
    @State private var onlySelected = true
    @State private var navigator = CommandHistoryNavigator()
    @State private var suggestionIndex = 0
    @State private var dismissed = false
    @State private var browsing = false
    @State private var historyInsertion: String?
    @State private var showShortcuts = false
    @FocusState private var focused: Bool
    init(model: AppModel, openManagement: @escaping () -> Void) {
        self.model = model; self.preferences = model.preferences; self.openManagement = openManagement
    }
    private var suggestions: [ConsoleCatalog.Suggestion] {
        guard !dismissed, browsing || (preferences.consoleSuggestions && !model.command.isEmpty) else { return [] }
        return ConsoleCatalog.suggestions(for:model.command,history:model.history,includeHistory:preferences.consoleHistory,includeChanges:preferences.consoleChanges,limit:5)
    }
    private var selectedSuggestion: ConsoleCatalog.Suggestion? {
        suggestions.indices.contains(suggestionIndex) ? suggestions[suggestionIndex] : suggestions.first
    }
    private var helpEntry: ConsoleCatalog.Entry? { selectedSuggestion?.entry ?? ConsoleCatalog.entry(for:model.command) }
    private let quickCommands: [(String,String,String)] = [
        ("Firmware","ver","shippingbox"),("Hardware","board","cpu"),("Název","get name","textformat"),("Rádio","get radio","wave.3.right"),("Sousedé","neighbors","point.3.connected.trianglepath.dotted"),("Hodiny","clock","clock")
    ]
    private var lines: [ConsoleLine] {
        model.console.filter { line in
            (!onlySelected || model.selectedID == nil || line.targetID == model.selectedID) && (search.isEmpty || line.command.localizedStandardContains(search) || line.response.localizedStandardContains(search))
        }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            PageHeading(eyebrow:"Přímý přístup k repeateru",title:"Vzdálená konzole",subtitle:"CLI příkazy a skutečné odpovědi, přehledně v jedné relaci.") {
                RepeaterPicker(model:model).labelsHidden().frame(width:210)
            }
            if !model.admin {
                HStack { Label("Pro odesílání se přihlaste ve správě repeateru.",systemImage:"lock").font(.callout).foregroundStyle(.secondary); Spacer(); Button("Otevřít přihlášení",action:openManagement) }
            }
            HStack(spacing:8) {
                Text("VLOŽIT PŘÍKAZ").font(.system(size:9,weight:.semibold)).tracking(1).foregroundStyle(.secondary)
                ForEach(quickCommands,id:\.1) { item in
                    Button { model.command = item.1; navigator.reset(); focused = true } label: { Label(item.0,systemImage:item.2).font(.caption) }.help("Vložit \(item.1). Odešlete tlačítkem nebo Enterem.")
                }
            }
            HStack {
                HStack { Image(systemName:"magnifyingglass").foregroundStyle(.secondary); TextField("Hledat v příkazech a odpovědích…",text:$search).textFieldStyle(.plain) }.padding(9).background(MeshTheme.surface,in:RoundedRectangle(cornerRadius:8))
                Toggle("Jen vybraný repeater",isOn:$onlySelected).toggleStyle(.checkbox).font(.caption)
                Button { model.console.removeAll() } label: { Image(systemName:"trash") }.disabled(model.busy || model.console.isEmpty).help("Vymazat historii konzole z paměti")
            }
            terminal.layoutPriority(-1)
            if !suggestions.isEmpty || (preferences.consoleHelp && helpEntry != nil) { assistance.frame(height:160) }
            composer
            HStack {
                Label("Tab doplnit · ↑ ↓ \(suggestions.isEmpty ? "historie" : "návrhy") · Esc zavřít" + (preferences.consoleEnterSends ? " · Enter odeslat" : ""),systemImage:"keyboard").font(.caption)
                Spacer()
                Text("Citlivé příkazy a odpovědi jsou skryté v historii.").font(.caption)
            }.foregroundStyle(.secondary)
        }.padding(28)
            .onChange(of:model.command) { _,value in
                suggestionIndex = 0
                dismissed = historyInsertion == value
                historyInsertion = nil
                if !dismissed { navigator.reset() }
            }
            .onChange(of:preferences.consoleChanges) { _,_ in suggestionIndex = 0 }
            .sheet(isPresented:$showShortcuts) { ConsoleShortcutsView(model:model,library:model.library) }
    }
    private var assistance: some View {
        HStack(alignment:.top,spacing:16) {
            if !suggestions.isEmpty {
                VStack(alignment:.leading,spacing:3) {
                    Text("\(browsing ? "KATALOG" : "DOPLNIT") · TAB VLOŽÍ NÁVRH").font(.system(size:9,weight:.semibold)).tracking(1).foregroundStyle(.secondary)
                    ForEach(Array(suggestions.enumerated()),id:\.element.id) { index,suggestion in
                        Button { accept(suggestion) } label: {
                            HStack(spacing:6) {
                                Image(systemName:suggestion.fromHistory ? "clock.arrow.circlepath" : (suggestion.entry?.changesState == true ? "pencil.circle" : "text.alignleft")).frame(width:15)
                                Text(suggestion.insertion).font(.system(size:11,design:.monospaced)).lineLimit(1)
                                Spacer(minLength:0)
                                if suggestion.entry?.changesState == true { Text("Změna").font(.system(size:9)).foregroundStyle(.orange) }
                            }.padding(.horizontal,7).padding(.vertical,5).contentShape(Rectangle())
                                .background(index == suggestionIndex ? MeshTheme.accent.opacity(0.12) : .clear,in:RoundedRectangle(cornerRadius:5))
                        }.buttonStyle(.plain).help(suggestion.entry?.syntax ?? "Vložit z místní historie")
                    }
                }.frame(maxWidth:preferences.consoleHelp ? 310 : .infinity,alignment:.leading)
            }
            if preferences.consoleHelp, let entry = helpEntry {
                ScrollView {
                VStack(alignment:.leading,spacing:7) {
                    HStack {
                        Text(entry.title).font(.callout.weight(.semibold))
                        Spacer()
                        Text(entry.changesState ? "Mění stav uzlu" : "Čtení po LoRa").font(.caption2).foregroundStyle(entry.changesState ? .orange : .secondary)
                    }
                    Text(entry.syntax).font(.system(size:11,design:.monospaced)).textSelection(.enabled)
                    Text(entry.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    Text("Katalog v1.18 · Podpora závisí na firmwaru uzlu.").font(.caption2).foregroundStyle(.secondary)
                    CommandEvidenceLabel(model:model,library:model.library,command:entry.command)
                }.frame(maxWidth:.infinity,alignment:.leading)
                }
            }
        }.padding(12).background(MeshTheme.surface,in:RoundedRectangle(cornerRadius:10))
    }
    private var terminal: some View {
        VStack(spacing:0) {
            HStack(spacing:8) {
                Image(systemName:"terminal").foregroundStyle(.white.opacity(0.5))
                Text(model.selected?.name ?? "Žádný repeater").foregroundStyle(.white.opacity(0.85))
                Text("/ LoRa").foregroundStyle(.white.opacity(0.35))
                Spacer()
                Text("\(lines.count) záznamů").foregroundStyle(.white.opacity(0.4))
            }.font(.system(size:11,design:.monospaced)).padding(14).background(.white.opacity(0.035))
            Divider().overlay(.white.opacity(0.08))
            ScrollViewReader { proxy in
                ScrollView {
                    if lines.isEmpty {
                        VStack(alignment:.leading,spacing:12) {
                            Text("MeshCore · vzdálené CLI").foregroundStyle(.white.opacity(0.75))
                            Text(search.isEmpty ? "Vyberte repeater a přihlaste se jako správce.\nZačněte příkazem ver nebo get radio.\n\nRychlé příkazy se nejprve vloží do vstupního řádku." : "Žádný záznam neodpovídá hledání.").foregroundStyle(.white.opacity(0.38))
                        }.font(.system(size:12,design:.monospaced)).frame(maxWidth:.infinity,alignment:.leading).padding(24)
                    }
                    LazyVStack(alignment:.leading,spacing:0) {
                        ForEach(lines) { line in
                            VStack(alignment:.leading,spacing:9) {
                                HStack(spacing:8) {
                                    Text(line.date.formatted(date:.omitted,time:.standard)).foregroundStyle(.white.opacity(0.35))
                                    Text(line.target).foregroundStyle(.white.opacity(0.5))
                                    Spacer()
                                    commandState(line.state)
                                }.font(.system(size:10,design:.monospaced))
                                Text("❯ " + line.command).foregroundStyle(Color(red:0.39,green:0.88,blue:0.74)).textSelection(.enabled)
                                Text(line.response).foregroundStyle(line.state == .failed ? Color.orange : Color.white.opacity(0.85)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                            }.font(.system(size:12,design:.monospaced)).padding(18).frame(maxWidth:.infinity,alignment:.leading).id(line.id)
                            Rectangle().fill(.white.opacity(0.06)).frame(height:1)
                        }
                    }
                }.onChange(of:model.console.count) { _,_ in if let id = lines.last?.id { withAnimation(.easeOut(duration:0.2)) { proxy.scrollTo(id,anchor:.bottom) } } }
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Color(red:0.065,green:0.078,blue:0.09),in:RoundedRectangle(cornerRadius:12)).clipShape(RoundedRectangle(cornerRadius:12))
    }
    private var composer: some View {
        HStack(spacing:12) {
            Text("❯").font(.system(size:18,weight:.medium,design:.monospaced)).foregroundStyle(MeshTheme.accent)
            TextField("Příkaz nebo český název v katalogu…",text:$model.command).textFieldStyle(.plain).font(.system(size:13,design:.monospaced)).focused($focused).onSubmit { if preferences.consoleEnterSends { send() } }
                .onKeyPress(.upArrow) { navigate(-1); return .handled }
                .onKeyPress(.downArrow) { navigate(1); return .handled }
                .onKeyPress(.tab) { guard let suggestion = selectedSuggestion else { return .ignored }; accept(suggestion); return .handled }
                .onKeyPress(.escape) { dismissed = true; browsing = false; return .handled }
            Text("\(model.command.utf8.count)/133 B").font(.system(size:10,design:.monospaced)).foregroundStyle(model.command.utf8.count > 133 ? .orange : .secondary)
            Menu { ForEach(model.history,id:\.self) { value in Button(model.clean(value)) { model.command = value; navigator.reset(); focused = true } } } label: { Image(systemName:"clock.arrow.circlepath") }.menuStyle(.borderlessButton).frame(width:24).help("Historie příkazů")
            Button { browsing.toggle(); dismissed = false; suggestionIndex = 0; focused = true } label: { Image(systemName:"book.closed") }.help("Katalog příkazů · hledá i podle českého názvu")
            Button { showShortcuts = true } label: { Image(systemName:"star") }.help("Oblíbené příkazy a pojmenované šablony")
            SettingsLink { Image(systemName:"slider.horizontal.3") }.help("Nastavení konzole a našeptávání")
            Button(action:send) { Label("Odeslat",systemImage:"arrow.up") }.buttonStyle(.borderedProminent).disabled(!model.admin || model.busy || model.command.isEmpty || model.command.utf8.count > 133)
        }.padding(14).background(MeshTheme.surface,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).strokeBorder(focused ? MeshTheme.accent.opacity(0.5) : MeshTheme.border))
            .disabled(model.busy)
    }
    private func accept(_ suggestion: ConsoleCatalog.Suggestion) {
        model.command = suggestion.insertion; navigator.reset(); browsing = false; focused = true
    }
    private func navigate(_ direction: Int) {
        if !suggestions.isEmpty {
            suggestionIndex = (suggestionIndex + direction + suggestions.count) % suggestions.count
        } else {
            let value = direction < 0 ? navigator.previous(current:model.command,history:model.history) : navigator.next(current:model.command,history:model.history)
            historyInsertion = value; model.command = value
            // Keep history navigation active until the user edits the command.
            dismissed = true
        }
    }
    private func send() {
        guard model.admin, !model.busy, !model.command.isEmpty, model.command.utf8.count <= 133 else { return }
        navigator.reset(); model.sendCLI()
    }
    @ViewBuilder private func commandState(_ state: CommandState) -> some View {
        switch state {
        case .waiting: Label("Čekám na odpověď",systemImage:"clock").foregroundStyle(.white.opacity(0.5))
        case .replied: Label("Odpověď přijata",systemImage:"checkmark.circle").foregroundStyle(.mint)
        case .sentWithoutReply: Label("Odesláno · provedení neověřeno",systemImage:"arrow.up.circle").foregroundStyle(.orange)
        case .failed: Label("Operace selhala",systemImage:"exclamationmark.circle").foregroundStyle(.orange)
        }
    }
}
