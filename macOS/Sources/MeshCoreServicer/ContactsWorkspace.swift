import SwiftUI
import MeshCoreKit

struct ContactsWorkspace: View {
    @ObservedObject var model: AppModel
    var openRepeater: () -> Void
    var openMessages: () -> Void
    @State private var search = ""
    @State private var scope: ContactScope = .all
    @State private var inspectedID: String?
    private var filtered: [Contact] { ContactQuery.filter(model.contacts,search:search,scope:scope) }
    private var inspected: Contact? { model.contacts.first { $0.id == inspectedID } }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            PageHeading(eyebrow:"Síťové uzly",title:"Kontakty",subtitle:"Uložené identity a nově objevené uzly na jednom místě.") {
                HStack { Button { model.loadContacts() } label: { Label("Načíst",systemImage:"arrow.clockwise") }; Button { model.discover() } label: { Label("Objevit repeatery",systemImage:"dot.radiowaves.left.and.right") }.buttonStyle(.borderedProminent) }.disabled(!model.initialized || model.busy)
            }
            HStack(spacing:16) {
                countTile("Všechny uzly",count:model.contacts.count,symbol:"network")
                countTile("Repeatery",count:model.contacts.filter { $0.kind == 2 }.count,symbol:"antenna.radiowaves.left.and.right")
                countTile("Neuložené",count:model.contacts.filter { !$0.stored }.count,symbol:"sparkle.magnifyingglass")
            }
            HStack(spacing:12) {
                HStack { Image(systemName:"magnifyingglass").foregroundStyle(.secondary); TextField("Hledat podle názvu, klíče nebo typu…",text:$search).textFieldStyle(.plain); if !search.isEmpty { Button { search = "" } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) } }.padding(10).background(MeshTheme.surface,in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).strokeBorder(MeshTheme.border))
                Picker("Zobrazit",selection:$scope) { ForEach(ContactScope.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width:160)
            }
            if let end = model.discoveryEnds {
                TimelineView(.periodic(from:.now,by:1)) { context in
                    if end > context.date {
                        HStack { ProgressView().controlSize(.mini); Text("Přijímám odpovědi discovery…"); Spacer(); Text("\(max(0,Int(ceil(end.timeIntervalSince(context.date))))) s").monospacedDigit() }.font(.caption).foregroundStyle(MeshTheme.accent)
                    }
                }
            }
            HStack(alignment:.top,spacing:16) {
                nodeList
                inspector.frame(width:270)
            }.frame(maxHeight:.infinity)
            Text("Uložení kontaktu a čas advertu neprokazují aktuální dostupnost. Ověření odpovědí má vždy vlastní čas.").font(.caption).foregroundStyle(.secondary)
        }.padding(28)
    }
    private var nodeList: some View {
        VStack(spacing:0) {
            HStack { Text("UZEL / ULOŽENÁ CESTA"); Spacer(); Text("\(filtered.count) z \(model.contacts.count)") }.font(.system(size:9,weight:.semibold)).tracking(0.8).foregroundStyle(.secondary).padding(14)
            Divider()
            if filtered.isEmpty {
                EmptyWorkspace(symbol:search.isEmpty ? "person.2" : "magnifyingglass",title:search.isEmpty ? "Kontakty zatím nejsou načtené" : "Žádný odpovídající uzel",message:search.isEmpty ? "Připojte companion a načtěte kontakty. Objevování repeaterů spustíte samostatně." : "Zkuste jiný název, část klíče nebo filtr.")
            } else {
                List(filtered,selection:$inspectedID) { c in
                    HStack(spacing:11) {
                        NodeAvatar(kind:c.kind,size:36)
                        VStack(alignment:.leading,spacing:4) {
                            Text(c.name).font(.callout.weight(.semibold)).lineLimit(1)
                            Text("\(c.kindName) · \(MeshPresentation.route(c))").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            Text(String(c.id.prefix(12))).font(.system(size:9,design:.monospaced)).foregroundStyle(.tertiary)
                        }
                        Spacer(minLength:4)
                        VStack(alignment:.trailing,spacing:5) {
                            Text(c.stored ? "Uloženo" : "Nový uzel").font(.system(size:10,weight:.medium)).foregroundStyle(c.stored ? Color.secondary : MeshTheme.accent)
                            if let date = model.verified[c.id] { Text(date,style:.relative).font(.system(size:10)).foregroundStyle(.secondary).help("Čas ověření odpovědí; nejedná se o trvalý online stav") }
                        }
                    }.padding(.vertical,8).tag(c.id)
                    .contextMenu {
                        if c.kind == 1 && c.stored { Button("Napsat zprávu") { model.messages.select("dm:"+c.key.prefix(6).hex); openMessages() } }
                        if c.kind == 2 { Button("Spravovat repeater") { manage(c) }.disabled(model.busy) }
                        Button("Zkopírovat veřejný klíč") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(c.id,forType:.string) }
                        if !c.stored { Button("Uložit kontakt do companionu") { model.storeContact(c) }.disabled(!model.initialized || model.busy) }
                    }
                }.listStyle(.inset).scrollContentBackground(.hidden)
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(MeshTheme.surface,in:RoundedRectangle(cornerRadius:12)).clipShape(RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).strokeBorder(MeshTheme.border))
    }
    @ViewBuilder private var inspector: some View {
        if let c = inspected {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    HStack { NodeAvatar(kind:c.kind,size:48); Spacer(); StatusPill(text:c.kindName,symbol:nodeSymbol(c.kind),color:nodeColor(c.kind)) }
                    Text(c.name).font(.title3.weight(.semibold))
                    KeyLabel(key:c.id)
                    Divider()
                    VStack(alignment:.leading,spacing:12) {
                        detail("Kontakt",c.stored ? "Uložený v companionu" : "Zatím neuložený")
                        detail("Uložená cesta",MeshPresentation.route(c))
                        detail("Dostupnost",model.verified[c.id].map { "Odpověď \($0.formatted(date:.abbreviated,time:.standard))" } ?? "Neověřená")
                        if c.lastAdvert > 0 { detail("Advert podle companionu",Date(timeIntervalSince1970:Double(c.lastAdvert)).formatted(date:.abbreviated,time:.shortened)) }
                    }
                    if let signal = model.discovered[c.id] { MessageBanner(title:"Odpověď discovery",message:signal,symbol:"wave.3.right") }
                    if !c.stored { Button { model.storeContact(c) } label: { Label("Uložit do companionu",systemImage:"plus") }.disabled(!model.initialized || model.busy) }
                    if c.kind == 1 && c.stored { Button { model.messages.select("dm:"+c.key.prefix(6).hex); openMessages() } label: { Label("Napsat zprávu",systemImage:"bubble.left") }.buttonStyle(.borderedProminent) }
                    if c.kind == 2 { Button { manage(c) } label: { Label("Spravovat repeater",systemImage:"arrow.right") }.buttonStyle(.borderedProminent).disabled(model.busy) }
                }.padding(18).frame(maxWidth:.infinity,alignment:.leading)
            }.background(MeshTheme.surface,in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).strokeBorder(MeshTheme.border))
        } else {
            VStack(spacing:12) { Image(systemName:"sidebar.right").font(.system(size:28,weight:.light)); Text("Vyberte uzel").font(.headline); Text("Podrobnosti a akce se zobrazí tady.").font(.caption).multilineTextAlignment(.center) }.foregroundStyle(.secondary).padding(24).frame(maxWidth:.infinity,maxHeight:.infinity)
        }
    }
    private func manage(_ c: Contact) { model.selectRepeater(c.id,then:openRepeater) }
    private func detail(_ label: String,_ value: String) -> some View { VStack(alignment:.leading,spacing:5) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value).font(.callout).textSelection(.enabled) } }
    private func countTile(_ title: String,count: Int,symbol: String) -> some View {
        HStack(spacing:12) { Image(systemName:symbol).foregroundStyle(MeshTheme.accent); Text("\(count)").font(.system(size:23,weight:.semibold,design:.rounded)).monospacedDigit(); Text(title).font(.caption).foregroundStyle(.secondary); Spacer(minLength:0) }.padding(14).frame(maxWidth:.infinity).background(MeshTheme.surface,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).strokeBorder(MeshTheme.border))
    }
}
