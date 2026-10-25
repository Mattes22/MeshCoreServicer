import SwiftUI
import MeshCoreKit

struct ConnectionWorkspace: View {
    @ObservedObject var model: AppModel
    @ObservedObject var ble: BluetoothTransport
    var openContacts: () -> Void
    var body: some View {
        WorkspaceScroll {
            PageHeading(eyebrow:"Váš vstup do sítě",title:"Spojení začíná companionem",subtitle:"Vyberte MeshCore companion a spravujte repeatery přes LoRa.") { EmptyView() }
            connectionCard
            linkPath
            CompanionProfilesView(model:model,library:model.library)
            if ble.ready {
                LazyVGrid(columns:MeshTheme.columns,spacing:12) {
                    MetricTile(title:"Companion",value:model.selfInfo?.name ?? "Načítám…",symbol:"cpu",detail:model.deviceInfo?.model)
                    MetricTile(title:"Baterie companionu",value:model.battery.map { String(format:"%.3f V",Double($0)/1000) } ?? "—",symbol:"battery.75percent",detail:"Napětí hlášené companionem")
                    MetricTile(title:"Firmware",value:model.deviceInfo?.version ?? "—",symbol:"shippingbox",detail:model.deviceInfo?.build)
                }
                if let s = model.selfInfo {
                    Panel(title:"Rádio companionu",symbol:"wave.3.right",subtitle:"Skutečně načtené nastavení; připojením se nemění.") {
                        HStack(spacing:24) {
                            radioItem("Frekvence",String(format:"%.3f MHz",s.frequency))
                            radioItem("Šířka pásma",String(format:"%g kHz",s.bandwidth))
                            radioItem("Spreading factor","SF\(s.sf)")
                            radioItem("Coding rate","4/\(s.cr)")
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                }
            }
            HStack(alignment:.top,spacing:16) {
                Panel(title:"Před prvním připojením",symbol:"checklist") {
                    VStack(alignment:.leading,spacing:13) {
                        checklist("1","Zapněte companion","Companion musí mít Bluetooth firmware.")
                        checklist("2","Odpojte telefon","Jiná aplikace může mít obsazené BLE spojení.")
                        checklist("3","Potvrďte párování macOS","Systém si případně vyžádá PIN zařízení.")
                    }
                }
                Panel(title:"Zařízení se nedaří najít?",symbol:"questionmark.circle") {
                    VStack(alignment:.leading,spacing:12) {
                        Text("Zkontrolujte Bluetooth, dosah a oprávnění aplikace v Soukromí a zabezpečení.").font(.callout).foregroundStyle(.secondary)
                        Text("Název v seznamu může obsahovat prefix firmwaru. Ověřte jej po připojení podle informací companionu.").font(.caption).foregroundStyle(.secondary)
                        Button("Zkusit poslední companion") { ble.reconnect() }.disabled(ble.ready || ble.connecting || model.busy)
                    }
                }
            }
        }
    }
    private var connectionCard: some View {
        VStack(alignment:.leading,spacing:22) {
            HStack(spacing:18) {
                Image(systemName:ble.ready ? "antenna.radiowaves.left.and.right" : "cable.connector")
                    .font(.system(size:33,weight:.light)).foregroundStyle(MeshTheme.accent)
                    .frame(width:76,height:76).background(MeshTheme.accent.opacity(0.10),in:RoundedRectangle(cornerRadius:22))
                VStack(alignment:.leading,spacing:7) {
                    HStack { Text(ble.ready ? model.selfInfo?.name ?? ble.connectedName : "Připojit companion").font(.title2.weight(.semibold)); StatusPill(text:ble.ready ? "BLE připojeno" : ble.connecting ? "Připojuji" : "Odpojeno",color:ble.ready ? .teal : .secondary) }
                    Text(ble.state).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }
                Spacer(minLength:0)
            }
            HStack(spacing:10) {
                if ble.ready {
                    Button(action:openContacts) { Label("Přejít na kontakty",systemImage:"arrow.right") }.buttonStyle(.borderedProminent).disabled(!model.initialized || model.busy)
                    Button("Odpojit") { ble.disconnect() }
                } else {
                    Button { if ble.scanning { ble.stopScan() } else { model.scanCompanions() } } label: { Label(ble.scanning ? "Zastavit hledání" : "Hledat companiony",systemImage:ble.scanning ? "stop.circle" : "magnifyingglass") }
                        .buttonStyle(.borderedProminent).disabled(ble.connecting || model.busy)
                    if ble.connecting { ProgressView().controlSize(.small); Button("Zrušit připojování") { ble.disconnect() } }
                    else if ble.retryDate != nil { Button("Zastavit obnovování") { ble.disconnect() } }
                }
                Spacer()
                Label("Bluetooth Low Energy",systemImage:"lock.shield").font(.caption).foregroundStyle(.secondary)
            }.controlSize(.large)
            if !ble.ready && (ble.scanning || !ble.devices.isEmpty) {
                Divider()
                HStack { Text("DOSTUPNÁ ZAŘÍZENÍ").font(.system(size:10,weight:.semibold)).tracking(1).foregroundStyle(.secondary); Spacer(); if ble.scanning { ProgressView().controlSize(.mini); Text("Skenování…").font(.caption).foregroundStyle(.secondary) } }
                if ble.devices.isEmpty {
                    Text("Čekám na BLE advert. Přibližte companion a uvolněte spojení v telefonu.").font(.callout).foregroundStyle(.secondary).padding(.vertical,10)
                }
                ForEach(ble.devices) { d in
                    HStack(spacing:12) {
                        NodeAvatar(kind:1,size:36)
                        VStack(alignment:.leading,spacing:4) { Text(d.name).font(.headline); Text(d.id.uuidString).font(.system(size:10,design:.monospaced)).foregroundStyle(.tertiary) }
                        Spacer(minLength:4)
                        Text("\(d.rssi) dBm").font(.caption.monospacedDigit()).foregroundStyle(.secondary).help("RSSI BLE advertu přijatého Macem")
                        Button("Připojit") { model.connectDevice(d.id) }.disabled(ble.connecting || model.busy)
                    }.padding(12).background(.quaternary.opacity(0.4),in:RoundedRectangle(cornerRadius:10))
                }
            }
        }.padding(24).background(MeshTheme.surface,in:RoundedRectangle(cornerRadius:18))
            .overlay(RoundedRectangle(cornerRadius:18).strokeBorder(MeshTheme.accent.opacity(0.20)))
    }
    private var linkPath: some View {
        HStack(spacing:0) {
            pathNode("desktopcomputer","Váš Mac","MeshCore Servicer",active:true)
            pathConnector("BLE",active:ble.ready)
            pathNode("cpu",ble.ready ? model.selfInfo?.name ?? ble.connectedName : "Companion",model.deviceInfo?.model ?? "Bluetooth companion",active:ble.ready)
            pathConnector("LoRa",active:false)
            pathNode("antenna.radiowaves.left.and.right",model.selected?.name ?? "Repeater","Vzdálená správa",active:false)
        }.padding(.vertical,20).padding(.horizontal,24).background(.quaternary.opacity(0.4),in:RoundedRectangle(cornerRadius:14))
            .accessibilityElement(children:.combine)
    }
    private func pathNode(_ icon: String,_ name: String,_ caption: String,active: Bool) -> some View {
        VStack(spacing:7) {
            Image(systemName:icon).font(.system(size:23,weight:.light)).foregroundStyle(active ? MeshTheme.accent : Color.secondary)
            Text(name).font(.callout.weight(.medium)).lineLimit(1)
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity)
    }
    private func pathConnector(_ label: String,active: Bool) -> some View {
        VStack(spacing:5) { Text(label).font(.system(size:9,weight:.bold)).tracking(1); Image(systemName:"arrow.left.arrow.right").font(.system(size:17,weight:.light)) }.foregroundStyle(active ? MeshTheme.accent : Color.secondary.opacity(0.6)).frame(width:65)
    }
    private func radioItem(_ label: String,_ value: String) -> some View { VStack(alignment:.leading,spacing:7) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value).font(.system(.body,design:.monospaced)).textSelection(.enabled) }.frame(maxWidth:.infinity,alignment:.leading) }
    private func checklist(_ number: String,_ title: String,_ detail: String) -> some View {
        HStack(alignment:.top,spacing:10) {
            Text(number).font(.caption.weight(.semibold)).foregroundStyle(MeshTheme.accent).frame(width:24,height:24).background(MeshTheme.accent.opacity(0.08),in:Circle())
            VStack(alignment:.leading,spacing:3) { Text(title).font(.callout.weight(.medium)); Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
