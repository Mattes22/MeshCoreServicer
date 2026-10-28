import SwiftUI
import MeshCoreKit

struct DiagnosticsWorkspace: View {
    @ObservedObject var model: AppModel
    @ObservedObject var ble: BluetoothTransport
    @State private var search = ""
    @State private var level: String = "all"
    @State private var selectedLog: UUID?
    @State private var sheet: DiagnosticsSheet?
    private var filtered: [LogLine] {
        model.logs.filter { (level == "all" || $0.level.rawValue == level) && (search.isEmpty || $0.text.localizedStandardContains(search)) }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            PageHeading(eyebrow:"Průběh relace",title:"Diagnostika",subtitle:"Události, chyby a stav spojení s časovým záznamem.") {
                HStack {
                    Button { sheet = .hardware } label: { Label("Kompatibilita",systemImage:"checklist") }
                    Button { sheet = .report } label: { Label("Report s náhledem…",systemImage:"square.and.arrow.up") }
                }
            }
            HStack(alignment:.top,spacing:14) {
                diagnosticSummary("Transport companionu",value:model.directUSB ? model.usb.state : model.linkReady ? model.linkLabel+" připojeno" : "Odpojeno",symbol:"cable.connector",color:model.linkReady ? .teal : .secondary)
                diagnosticSummary("Companion protokol",value:model.deviceInfo.map { "v\($0.protocolVersion)" } ?? "Nenačteno",symbol:"shippingbox",color:.secondary)
                diagnosticSummary("Události v relaci",value:"\(model.logs.count)",symbol:"list.bullet.rectangle",color:.secondary)
            }
            HStack(spacing:12) {
                HStack { Image(systemName:"magnifyingglass").foregroundStyle(.secondary); TextField("Hledat v diagnostice…",text:$search).textFieldStyle(.plain) }.padding(10).background(MeshTheme.surface,in:RoundedRectangle(cornerRadius:8))
                Picker("Úroveň",selection:$level) { Text("Všechny události").tag("all"); ForEach(LogLevel.allCases,id:\.self) { Text($0.rawValue).tag($0.rawValue) } }.labelsHidden().frame(width:160)
                Button { model.logs.removeAll() } label: { Image(systemName:"trash") }.disabled(model.logs.isEmpty).help("Vymazat log z paměti")
            }
            VStack(spacing:0) {
                HStack { Text("ČAS").frame(width:80,alignment:.leading); Text("UDÁLOST"); Spacer(); Text("\(filtered.count) záznamů") }.font(.system(size:9,weight:.semibold)).tracking(1).foregroundStyle(.secondary).padding(14)
                Divider()
                if filtered.isEmpty {
                    EmptyWorkspace(symbol:"waveform.path.ecg",title:model.logs.isEmpty ? "Relace zatím nemá události" : "Žádné odpovídající záznamy",message:model.logs.isEmpty ? "Záznamy se objeví při připojení a práci s companionem." : "Změňte filtr nebo hledaný text.")
                } else {
                    List(filtered.reversed(),selection:$selectedLog) { line in
                        HStack(alignment:.top,spacing:12) {
                            Text(line.date.formatted(date:.omitted,time:.standard)).font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary).frame(width:73,alignment:.leading)
                            Image(systemName:line.level == .error ? "exclamationmark.circle.fill" : line.level == .warning ? "exclamationmark.triangle" : "circle.fill").font(.system(size:line.level == .info ? 5 : 12)).foregroundStyle(line.level == .info ? Color.secondary : Color.orange).frame(width:14,height:14)
                            Text(line.text).font(.system(size:11,design:.monospaced)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                        }.padding(.vertical,6).tag(line.id)
                    }.listStyle(.inset).scrollContentBackground(.hidden)
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity).background(MeshTheme.surface,in:RoundedRectangle(cornerRadius:12)).clipShape(RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).strokeBorder(MeshTheme.border))
            DisclosureGroup("O logování a protokolu") {
                VStack(alignment:.leading,spacing:9) {
                    Text("Log obsahuje provozní události bez surových rámců a bez textu CLI. Hesla, BLE PIN a privátní klíče se do něj neukládají. Historie konzole zůstává samostatně v paměti.")
                    Text("MeshCore 81dbae592ffad40b4212bc0b37e82b38da08f4bc\nmeshcore.js 26193c059fcd1d0524f1ad5b19fd88287ecc5c61").font(.system(size:10,design:.monospaced)).textSelection(.enabled)
                    Link("Oficiální dokumentace protokolu",destination:URL(string:"https://docs.meshcore.io/companion_protocol/")!)
                }.font(.caption).foregroundStyle(.secondary).padding(.top,8)
            }.font(.caption)
        }.padding(28).sheet(item:$sheet) { page in
            if page == .report { DiagnosticReportView(model:model) }
            else { HardwareVerificationView(model:model,library:model.library) }
        }
    }
    private func diagnosticSummary(_ title: String,value: String,symbol: String,color: Color) -> some View {
        HStack(spacing:11) {
            Image(systemName:symbol).font(.system(size:19,weight:.light)).foregroundStyle(color)
            VStack(alignment:.leading,spacing:5) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.callout.weight(.semibold)).monospacedDigit() }
            Spacer(minLength:0)
        }.padding(16).frame(maxWidth:.infinity).background(MeshTheme.surface,in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).strokeBorder(MeshTheme.border))
    }
}
