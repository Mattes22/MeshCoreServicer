import SwiftUI
import MeshCoreKit

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case connection = "Připojení", contacts = "Kontakty", messages = "Zprávy", repeater = "Správa repeateru", console = "Konzole", diagnostics = "Diagnostika"
    var id: String { rawValue }
    var icon: String {
        switch self { case .connection:return "cable.connector"; case .contacts:return "person.2"; case .messages:return "bubble.left.and.bubble.right"; case .repeater:return "antenna.radiowaves.left.and.right"; case .console:return "terminal"; case .diagnostics:return "waveform.path.ecg" }
    }
}
struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var ble: BluetoothTransport
    @Environment(\.colorScheme) private var colorScheme
    @State var section: WorkspaceSection? = .connection
    var repeaterTab: RepeaterTab = .overview
    var repeaterToolsSection: RepeaterToolSection = .diagnostics
    var operationsTab: OperationsTab = .health
    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing:0) {
                if let error = model.error {
                    MessageBanner(title:"Operace nebyla dokončena",message:error,symbol:"exclamationmark.triangle.fill",color:.orange,dismiss:{ model.error = nil }).padding([.horizontal,.top],20)
                } else if let notice = model.notice {
                    MessageBanner(title:notice,symbol:"checkmark.circle.fill",color:.teal,dismiss:{ model.notice = nil }).padding([.horizontal,.top],20)
                }
                workspace.frame(maxWidth:.infinity,maxHeight:.infinity)
                operationBar
            }.background(MeshTheme.canvas)
                .navigationTitle(section?.rawValue ?? "MeshCore Servicer")
                .toolbar {
                    ToolbarItem(placement:.principal) { connectionBadge }
                    ToolbarItemGroup(placement:.primaryAction) {
                        if ble.ready { Button { ble.disconnect() } label: { Image(systemName:"eject") }.help("Odpojit companion") }
                        SettingsLink { Image(systemName:"gearshape") }.help("Nastavení aplikace")
                        Button { section = .diagnostics } label: { Image(systemName:"waveform.path.ecg") }.help("Otevřít diagnostiku")
                    }
                }
        }
        .onAppear { routeNotification() }
        .onChange(of:model.showMessagesRequested) { _,_ in routeNotification() }
        .tint(MeshTheme.accent)
        .sheet(item:$model.confirmation) { c in
            VStack(alignment:.leading,spacing:20) {
                Image(systemName:"exclamationmark.triangle").font(.system(size:28)).foregroundStyle(.orange)
                Text(c.title).font(.title2.bold())
                ScrollView { Text(c.message).font(.callout).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }.frame(maxHeight:440)
                HStack { Spacer(); Button("Zrušit",role:.cancel) { model.confirmation = nil }.keyboardShortcut(.cancelAction); Button("Potvrdit") { model.confirmation = nil; c.action() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
            }.padding(28).frame(width:520)
        }
    }
    private func routeNotification() { if model.showMessagesRequested { section = .messages; model.showMessagesRequested = false } }
    private var sidebarText: Color { colorScheme == .dark ? Color(white:0.90) : Color(white:0.12) }
    private var sidebarSecondary: Color { colorScheme == .dark ? Color(white:0.65) : Color(white:0.42) }
    private var sidebarAccent: Color { colorScheme == .dark ? Color(red:0.35,green:0.83,blue:0.76) : Color(red:0.02,green:0.43,blue:0.39) }
    private var sidebar: some View {
        VStack(spacing:0) {
            HStack(spacing:11) {
                Image(systemName:"point.3.connected.trianglepath.dotted").font(.system(size:25,weight:.semibold)).foregroundColor(sidebarAccent)
                VStack(alignment:.leading,spacing:1) { Text("MeshCore").font(.system(size:20,weight:.bold,design:.rounded)); Text("SERVICER").font(.system(size:9,weight:.bold)).tracking(2).foregroundColor(sidebarSecondary) }
                Spacer()
            }.padding(.horizontal,20).padding(.top,24).padding(.bottom,25)
            VStack(alignment:.leading,spacing:5) {
                Text("PRACOVNÍ PROSTOR").font(.system(size:9,weight:.semibold)).tracking(1).foregroundColor(sidebarSecondary).padding(.horizontal,12).padding(.bottom,7)
                ForEach(Array(WorkspaceSection.allCases.enumerated()),id:\.element.id) { index,s in
                    Button { section = s } label: {
                        HStack(spacing:10) {
                            Image(systemName:s.icon).font(.system(size:15)).frame(width:20)
                            Text(s.rawValue).font(.system(size:13,weight:section == s ? .semibold : .regular))
                            Spacer(minLength:0)
                            if s == .contacts, !model.contacts.isEmpty { Text("\(model.contacts.count)").font(.caption.monospacedDigit()).foregroundColor(sidebarSecondary) }
                            if s == .messages { UnreadMessagesBadge(chat:model.messages) }
                            if s == .repeater, !model.dirtyKeys.isEmpty { Circle().fill(.orange).frame(width:6,height:6).accessibilityLabel("Neuložené změny") }
                        }.foregroundColor(section == s ? sidebarAccent : sidebarText)
                            .padding(.horizontal,12).frame(height:38).contentShape(Rectangle())
                            .background(section == s ? MeshTheme.accent.opacity(0.12) : Color.clear,in:RoundedRectangle(cornerRadius:8))
                    }.buttonStyle(.plain).keyboardShortcut(KeyEquivalent(Character(String(index+1))),modifiers:.command)
                        .help("⌘\(index+1) · \(s.rawValue)")
                }
            }.padding(.horizontal,10)
            Spacer(minLength:16)
            if let c = model.selected {
                VStack(alignment:.leading,spacing:9) {
                    Text("VYBRANÝ REPEATER").font(.system(size:9,weight:.semibold)).tracking(1).foregroundColor(sidebarSecondary)
                    HStack { NodeAvatar(kind:2,size:30).foregroundColor(sidebarAccent); Text(c.name).font(.callout.weight(.medium)).lineLimit(2) }
                    Label(model.admin ? "Správce ověřen" : "Bez přihlášení",systemImage:model.admin ? "lock.open" : "lock").font(.caption).foregroundColor(model.admin ? sidebarAccent : sidebarSecondary)
                }.padding(15).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary,in:RoundedRectangle(cornerRadius:12)).padding(12)
            }
            Divider().padding(.horizontal,16)
            Button { section = .connection } label: {
                HStack(spacing:10) {
                    Circle().fill(ble.ready ? Color.teal : Color.secondary).frame(width:7,height:7)
                    VStack(alignment:.leading,spacing:3) {
                        Text(ble.ready ? model.selfInfo?.name ?? ble.connectedName : "Companion odpojen").font(.callout.weight(.medium)).lineLimit(1)
                        Text(ble.ready ? "Připojeno přes Bluetooth" : "Vyberte Bluetooth zařízení").font(.caption2).foregroundColor(sidebarSecondary)
                    }
                    Spacer(minLength:0); Image(systemName:"chevron.right").font(.caption2).foregroundColor(sidebarSecondary)
                }.padding(18).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.foregroundColor(sidebarText).environment(\.colorScheme,colorScheme).navigationSplitViewColumnWidth(min:220,ideal:235,max:270)
    }
    private var connectionBadge: some View {
        HStack(spacing:8) {
            Image(systemName:"desktopcomputer").foregroundStyle(.secondary)
            Text("BLE").font(.system(size:9,weight:.bold)).foregroundStyle(.tertiary)
            Circle().fill(ble.ready ? Color.teal : Color.secondary).frame(width:6,height:6)
            Text(ble.ready ? model.selfInfo?.name ?? ble.connectedName : "Bez companionu").font(.caption.weight(.medium)).lineLimit(1)
            if ble.ready, let b = model.battery { Text(String(format:"%.2f V",Double(b)/1000)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
        }.padding(.horizontal,12).padding(.vertical,6).background(.quaternary,in:Capsule())
    }
    @ViewBuilder private var workspace: some View {
        switch section ?? .connection {
        case .connection: ConnectionWorkspace(model:model,ble:ble,openContacts:{ section = .contacts })
        case .contacts: ContactsWorkspace(model:model,openRepeater:{ section = .repeater },openMessages:{ section = .messages })
        case .messages: MessagesWorkspace(model:model,chat:model.messages)
        case .repeater: RepeaterWorkspace(model:model,openContacts:{ section = .contacts },openConsole:{ section = .console },tab:repeaterTab,toolsSection:repeaterToolsSection,operationsTab:operationsTab)
        case .console: ConsoleWorkspace(model:model,openManagement:{ section = .repeater })
        case .diagnostics: DiagnosticsWorkspace(model:model,ble:ble)
        }
    }
    private var operationBar: some View {
        HStack(spacing:10) {
            if model.busy { ProgressView().controlSize(.mini) }
            else { Image(systemName:model.error == nil ? "checkmark.circle" : "exclamationmark.circle").foregroundStyle(model.error == nil ? Color.secondary : .orange) }
            Text(model.progress).font(.caption).lineLimit(1).help(model.progress)
            if model.busy, model.totalSteps > 0 {
                ProgressView(value:Double(model.completedSteps),total:Double(model.totalSteps)).frame(width:85)
                Text("\(model.completedSteps)/\(model.totalSteps)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength:10)
            Text("BLE → companion · LoRa → repeater").font(.system(size:10,design:.monospaced)).foregroundStyle(.tertiary)
        }.padding(.horizontal,20).frame(height:36).background(.bar).overlay(alignment:.top) { Divider() }
    }
}
