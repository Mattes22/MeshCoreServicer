import SwiftUI
import MeshCoreKit

private struct ChatThread: Identifiable {
    let id: String
    var title: String
    var channel: Bool
    var current = false
    var preview = "Zatím žádné zprávy"
    var lastDate: Date = .distantPast
    var unread = 0
}
struct MessagesWorkspace: View {
    @ObservedObject var model: AppModel
    @ObservedObject var chat: MessagesModel
    @ObservedObject private var preferences: AppPreferences
    init(model: AppModel, chat: MessagesModel) { self.model = model; self.chat = chat; self.preferences = model.preferences }
    @State private var search = ""
    @State private var scope = "all"
    @FocusState private var focused: Bool
    private var allThreads: [ChatThread] {
        var table: [String:ChatThread] = [:]
        for c in chat.channels.values where c.configured { table[c.id] = ChatThread(id:c.id,title:c.name.isEmpty ? "Kanál \(c.index)" : c.name,channel:true,current:true) }
        for c in model.contacts where c.kind == 1 && c.stored {
            let id = "dm:" + c.key.prefix(6).hex
            table[id] = ChatThread(id:id,title:c.name,channel:false,current:true)
        }
        for r in chat.records {
            var t = table[r.conversationID] ?? ChatThread(id:r.conversationID,title:r.title,channel:r.channelIndex != nil)
            if r.date >= t.lastDate { t.lastDate = r.date; t.preview = r.text }
            if !r.outgoing && !r.seen { t.unread += 1 }
            table[t.id] = t
        }
        return table.values.sorted { $0.lastDate == $1.lastDate ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : $0.lastDate > $1.lastDate }
    }
    private var threads: [ChatThread] { allThreads.filter { t in
        (scope == "all" || (scope == "channels" ? t.channel : !t.channel)) && (search.isEmpty || t.title.localizedStandardContains(search) || t.preview.localizedStandardContains(search))
    } }
    private var selected: ChatThread? { allThreads.first { $0.id == chat.selectedConversation } }
    private var selectedRecords: [ChatRecord] { chat.records.filter { $0.conversationID == chat.selectedConversation } }
    private var channel: ChannelInfo? { chat.channels.values.first { $0.id == chat.selectedConversation && $0.configured } }
    private var directPeer: Contact? {
        guard let id = chat.selectedConversation, id.hasPrefix("dm:") else { return nil }
        let matches = model.contacts.filter { "dm:"+$0.key.prefix(6).hex == id }
        return matches.count == 1 && matches[0].kind == 1 && matches[0].stored ? matches[0] : nil
    }
    private var draft: Binding<String> { Binding(get:{ chat.drafts[chat.selectedConversation ?? ""] ?? "" },set:{ if let id = chat.selectedConversation { chat.drafts[id] = $0 } }) }
    private var limit: Int { channel == nil ? MeshMessaging.maximumTextBytes : MeshMessaging.channelLimit(sender:model.selfInfo?.name ?? "") }
    private var canSend: Bool { model.initialized && chat.account != nil && !model.busy && (channel != nil || directPeer != nil) && !draft.wrappedValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && draft.wrappedValue.utf8.count <= limit && !draft.wrappedValue.utf8.contains(0) }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            PageHeading(eyebrow:"Komunikace přes companion",title:"Zprávy",subtitle:"Soukromé konverzace a kanály vaší MeshCore sítě.") {
                HStack {
                    Button { model.requestMessageSync(manual:true) } label: { Label("Přijmout zprávy",systemImage:"arrow.down.circle") }.disabled(!model.initialized || model.busy)
                    Menu {
                        Button("Načíst kanály companionu") { model.refreshChannels() }
                        Divider()
                        ForEach(model.contacts.filter { $0.kind == 1 && $0.stored }) { c in Button("Napsat: \(c.name)") { chat.select("dm:"+c.key.prefix(6).hex); focused = true } }
                    } label: { Image(systemName:"square.and.pencil") }.disabled(!model.initialized || model.busy).help("Nová konverzace a kanály")
                }
            }
            if let error = chat.storageError { MessageBanner(title:"Lokální historie",message:error,symbol:"externaldrive.badge.exclamationmark",color:.orange) }
            if let error = chat.syncError { MessageBanner(title:"Příjem se nepodařilo dokončit",message:error,symbol:"exclamationmark.circle",color:.orange) }
            HStack(spacing:0) {
                conversations.frame(width:270)
                Divider()
                conversation.frame(maxWidth:.infinity,maxHeight:.infinity)
            }.background(MeshTheme.surface,in:RoundedRectangle(cornerRadius:14)).clipShape(RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).strokeBorder(MeshTheme.border))
        }.padding(28)
            .onAppear { chat.visible = true; chat.markRead(); chat.expire() }
            .onDisappear { chat.visible = false }
            .onChange(of:chat.selectedConversation) { _,_ in chat.markRead() }
    }
    private var conversations: some View {
        VStack(spacing:0) {
            HStack { Image(systemName:"magnifyingglass").foregroundStyle(.secondary); TextField("Hledat konverzace…",text:$search).textFieldStyle(.plain) }.padding(14)
            Picker("Typ konverzace",selection:$scope) { Text("Vše").tag("all"); Text("Soukromé").tag("direct"); Text("Kanály").tag("channels") }.pickerStyle(.segmented).labelsHidden().padding([.horizontal,.bottom],12)
            Divider()
            if threads.isEmpty { EmptyWorkspace(symbol:"bubble.left.and.bubble.right",title:"Žádné konverzace",message:"Načtěte kontakty nebo kanály companionu.") }
            else {
                List(selection:Binding(get:{ chat.selectedConversation },set:{ chat.select($0) })) {
                    ForEach(threads) { thread in
                        HStack(alignment:.top,spacing:10) {
                            Image(systemName:thread.channel ? "number" : "person.wave.2").foregroundStyle(thread.channel ? MeshTheme.accent : Color.blue).frame(width:30,height:30).background(.quaternary,in:RoundedRectangle(cornerRadius:9))
                            VStack(alignment:.leading,spacing:5) {
                                HStack { Text(thread.title).font(.callout.weight(.semibold)).lineLimit(1); Spacer(minLength:2); if thread.unread > 0 { Text("\(thread.unread)").font(.system(size:10,weight:.semibold)).foregroundStyle(MeshTheme.accent) } }
                                Text(thread.preview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                if thread.lastDate != .distantPast { Text(thread.lastDate,style:.relative).font(.system(size:9)).foregroundStyle(.tertiary) }
                            }
                        }.padding(.vertical,8).tag(thread.id)
                    }
                }.listStyle(.inset).scrollContentBackground(.hidden)
            }
            Divider()
            HStack { Image(systemName:"internaldrive"); Text("Historie tohoto companionu").lineLimit(1) }.font(.system(size:10)).foregroundStyle(.secondary).padding(12)
        }
    }
    @ViewBuilder private var conversation: some View {
        if let id = chat.selectedConversation {
            VStack(spacing:0) {
                HStack(spacing:11) {
                    Image(systemName:channel != nil || selected?.channel == true ? "number" : "bubble.left.and.bubble.right").font(.system(size:19)).foregroundStyle(MeshTheme.accent)
                    VStack(alignment:.leading,spacing:4) {
                        Text(selected?.title ?? "Konverzace").font(.headline).lineLimit(1)
                        Text(channel != nil ? "Skupinový kanál · bez potvrzení doručení" : directPeer != nil ? "Soukromá zpráva přes companion a LoRa" : "Lokální historie · cíl není dostupný pro odesílání").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let account = chat.account, channel != nil {
                        let muted = preferences.isMuted(account:account,conversation:id)
                        Button {
                            preferences.mute(!muted,account:account,conversation:id)
                            if !muted { model.notifications.clearConversation(account:account,conversation:id) }
                        } label: { Label(muted ? "Ztišeno" : "Ztišit",systemImage:muted ? "bell.slash" : "bell") }.help("Ztišit bannery a zvuk tohoto kanálu; zprávy a nepřečtené počty zůstanou")
                    }
                }.padding(18)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment:.leading,spacing:18) {
                            if selectedRecords.isEmpty { EmptyWorkspace(symbol:"bubble.left",title:"Začněte konverzaci",message:"Zpráva se odešle až po stisknutí Odeslat. Return vloží nový řádek, ⌘Return odešle.") }
                            ForEach(selectedRecords) { record in ChatBubble(record:record).id(record.id) }
                        }.padding(20)
                    }.background(MeshTheme.canvas.opacity(0.6))
                        .onChange(of:id,initial:true) { _,_ in if let last = selectedRecords.last?.id { proxy.scrollTo(last,anchor:.bottom) } }
                        .onChange(of:chat.records.count) { _,_ in if let last = selectedRecords.last?.id { withAnimation(.easeOut(duration:0.15)) { proxy.scrollTo(last,anchor:.bottom) } } }
                }
                Divider()
                if !model.initialized { Label("Companion je odpojený. Historii můžete číst.",systemImage:"cable.connector").font(.caption).foregroundStyle(.secondary).padding(12) }
                else if channel == nil && directPeer == nil { Text("Pro odesílání vyberte aktuální kanál nebo jednoznačný companion kontakt. Repeatery a room servery se zde neoslovují.").font(.caption).foregroundStyle(.secondary).padding(12) }
                composer
            }
        } else { EmptyWorkspace(symbol:"bubble.left.and.bubble.right",title:"Vyberte konverzaci",message:"Zvolte companion kontakt nebo načtený kanál. Správa repeaterů zůstává oddělená v konzoli.") }
    }
    private var composer: some View {
        VStack(alignment:.leading,spacing:10) {
            ZStack(alignment:.topLeading) {
                if draft.wrappedValue.isEmpty { Text("Napište zprávu…").font(.callout).foregroundStyle(.tertiary).padding(8).allowsHitTesting(false) }
                TextEditor(text:draft).font(.callout).scrollContentBackground(.hidden).padding(3).focused($focused)
            }.frame(height:70).background(.quaternary.opacity(0.45),in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).strokeBorder(focused ? MeshTheme.accent.opacity(0.3) : MeshTheme.border))
            HStack {
                Text("\(draft.wrappedValue.utf8.count)/\(limit) UTF-8 B").font(.system(size:10,design:.monospaced)).foregroundStyle(draft.wrappedValue.utf8.count > limit ? .orange : .secondary)
                Spacer()
                if model.busy { ProgressView().controlSize(.mini) }
                Button { model.sendChat() } label: { Label("Odeslat",systemImage:"arrow.up") }.buttonStyle(.borderedProminent).disabled(!canSend).keyboardShortcut(.return,modifiers:.command)
            }
        }.padding(14)
    }
}
private struct ChatBubble: View {
    let record: ChatRecord
    var body: some View {
        HStack(alignment:.top) {
            if record.outgoing { Spacer(minLength:45) }
            VStack(alignment:.leading,spacing:9) {
                HStack {
                    Text(record.outgoing ? "Vy" : record.sender).font(.caption.weight(.semibold)).foregroundStyle(record.outgoing ? MeshTheme.accent : .secondary).lineLimit(1)
                        .help(record.channelIndex == nil ? "Odesílatel podle companionu" : "Jméno převzaté z textu kanálové zprávy; samo o sobě neověřuje identitu")
                    Spacer(minLength:10)
                    Text(Date(timeIntervalSince1970:Double(record.timestamp)).formatted(date:.abbreviated,time:.shortened)).font(.system(size:9)).foregroundStyle(.tertiary).help("Čas zprávy podle hodin odesílatele")
                }
                Text(record.text).font(.callout).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                Label(record.delivery.label,systemImage:deliverySymbol).font(.system(size:10)).foregroundStyle(deliveryColor)
                if let roundTrip = record.roundTrip { Text("ACK za \(roundTrip) ms").font(.system(size:9)).foregroundStyle(.secondary) }
                if let detail = record.detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
                if record.channelIndex != nil {
                    HStack(spacing:10) {
                        Label(record.hops.map { "\($0) přeposlání v cestě" } ?? "Cesta neuvedena",systemImage:"point.3.connected.trianglepath.dotted")
                        Spacer(minLength:0)
                        Label(record.capturedForwardings.map { "Zachyceno \($0) přeposlání" } ?? "Přeposlání nezjištěna",systemImage:"arrow.triangle.2.circlepath")
                    }.font(.system(size:10)).foregroundStyle(.secondary)
                        .help("Cesta: počet hopů přijatého paketu. Zachyceno: počet kopií stejného paketu, které companion předal aplikaci a měly alespoň jeden hop. Není to celkový počet přeposlání v síti ani potvrzení doručení.")
                    if let captures = record.captures, !captures.isEmpty {
                        DisclosureGroup("Zachycené kopie · posledních \(captures.count)") {
                            VStack(alignment:.leading,spacing:7) {
                                ForEach(captures.reversed()) { capture in
                                    Text(String(format:"%@ · %@ · RSSI %d dBm · SNR %.2f dB",capture.date.formatted(date:.omitted,time:.standard),capture.hops.map{"\($0) hopů"} ?? "neurčená/přímá cesta",capture.rssi,capture.snr)).font(.system(size:10,design:.monospaced)).textSelection(.enabled)
                                }
                                Text("Každý řádek je konkrétní příjem na companionu. Jen flood kopie s alespoň jedním hopem zvyšuje počet přeposlání. Identita repeateru se z těchto metrik neurčuje.").font(.caption2).foregroundStyle(.secondary)
                            }.padding(.top,6)
                        }.font(.caption).tint(MeshTheme.accent)
                    }
                    if let date = record.lastObservation { Text("Poslední zachycená kopie: \(date.formatted(date:.omitted,time:.standard))").font(.system(size:9)).foregroundStyle(.tertiary) }
                }
                if let snr = record.snr { Text(String(format:"Přijatá zpráva na companionu · SNR %.2f dB",snr)).font(.system(size:9)).foregroundStyle(.tertiary) }
            }.padding(14).frame(maxWidth:580,alignment:.leading)
                .background(record.outgoing ? MeshTheme.accent.opacity(0.08) : MeshTheme.surface,in:RoundedRectangle(cornerRadius:13))
                .overlay(RoundedRectangle(cornerRadius:13).strokeBorder(MeshTheme.border))
                .contextMenu { Button("Zkopírovat text") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(record.text,forType:.string) } }
            if !record.outgoing { Spacer(minLength:45) }
        }
    }
    private var deliverySymbol: String { switch record.delivery { case .acknowledged:return "checkmark.circle.fill"; case .received:return "arrow.down.left"; case .sending,.awaitingAcknowledgement:return "clock"; case .accepted:return "arrow.up.circle"; case .unconfirmed,.rejected:return "exclamationmark.circle" } }
    private var deliveryColor: Color { switch record.delivery { case .acknowledged:return MeshTheme.accent; case .unconfirmed,.rejected:return .orange; default:return .secondary } }
}
struct UnreadMessagesBadge: View {
    @ObservedObject var chat: MessagesModel
    var body: some View { if chat.unreadCount > 0 { Text("\(chat.unreadCount)").font(.caption.monospacedDigit()).foregroundStyle(MeshTheme.accent) } }
}
