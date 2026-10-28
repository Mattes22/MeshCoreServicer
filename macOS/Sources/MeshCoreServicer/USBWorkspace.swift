import SwiftUI
import MeshCoreKit

struct USBConnectionCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var usb: USBTransport
    @State private var port = ""
    @State private var mode: USBMode = .companion
    var openManagement: () -> Void
    var body: some View {
        Panel(title:"Připojení přes USB",symbol:"cable.connector",subtitle:"Companion s USB firmwarem, nebo přímá místní správa repeateru.") {
            VStack(alignment:.leading,spacing:14) {
                Picker("Režim USB",selection:$mode) {ForEach(USBMode.allCases,id:\.self) {Text($0.rawValue).tag($0)}}
                HStack {
                    Picker("Sériový port",selection:$port) {
                        Text("Vyberte port").tag("")
                        ForEach(usb.ports,id:\.self) {Text($0).tag($0)}
                    }
                    Button("Obnovit porty") {usb.refreshPorts()}
                }
                HStack {
                    Button("Připojit přes USB") {model.connectUSB(port,mode:mode)}.buttonStyle(.borderedProminent)
                        .disabled(port.isEmpty || model.busy || usb.connecting || model.usbRepeater.busy || model.ble.connecting)
                    Button("Odpojit USB") {model.disconnectAll()}.disabled(!usb.ready && !usb.connecting)
                    if model.directUSB && usb.ready {Button("Spravovat USB repeater",action:openManagement)}
                    if usb.connecting {ProgressView().controlSize(.small)}
                }
                Text(usb.state).font(.callout).foregroundStyle(.secondary)
                Text("115200 baud · 8N1 · datový USB kabel. BLE companion firmware nemusí USB protokol poskytovat; firmware se automaticky nemění. Otevření portu může podle desky vyvolat restart. Připojení neodesílá adverty ani změny konfigurace.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
struct USBRepeaterWorkspace: View {
    @ObservedObject var model: USBRepeaterModel
    @ObservedObject var usb: USBTransport
    @State private var key = "name"
    @State private var value = ""
    @State private var command = ""
    @State private var suggestion = ""
    private var enabled: Bool {model.ready && !model.busy && !usb.connecting}
    private var suggestions: [String] { ["ver","board","clock","stats-core","stats-radio","stats-packets","neighbors"]+CLIValidation.keys.map {"get "+$0} }
    var body: some View {
        WorkspaceScroll {
            PageHeading(eyebrow:"Místní USB správa",title:model.name,subtitle:"Přímé CLI bez companionu a bez vzdáleného přihlášení.") {EmptyView()}
            Text(model.firmware+" · "+model.board).foregroundStyle(.secondary)
            Text(model.progress).font(.callout)
            if let error = model.error {MessageBanner(title:"USB operace nebyla dokončena",message:error,symbol:"exclamationmark.triangle.fill",color:.orange,dismiss:{model.error = nil})}
            if !enabled {Text(model.busy ? "Probíhá USB požadavek…" : "Před dalším příkazem obnovte USB spojení.").foregroundStyle(.secondary)}
            Panel(title:"Nastavení a ověření zápisu",symbol:"slider.horizontal.3",subtitle:"Čtení a zápis konfigurace tohoto zařízení probíhají místně přes USB.") {
                VStack(alignment:.leading,spacing:14) {
                    Picker("Pole",selection:$key) {ForEach(CLIValidation.keys,id:\.self) { field in Text((ConsoleCatalog.entries.first{$0.command == "get "+field}?.title ?? field)+" (\(field))").tag(field)}}
                        .onChange(of:key) {_,_ in value = ""}
                    HStack {Button("Načíst hodnotu") {model.readSetting(key)};Text(model.values[key] ?? "Dosud nenačteno").textSelection(.enabled)}
                    Text(ConsoleCatalog.entries.first{$0.command == "set "+key}?.detail ?? "").font(.caption).foregroundStyle(.secondary)
                    TextField("Nová hodnota",text:$value)
                    Button("Zapsat a ověřit…") {model.apply(key,value)}
                }.disabled(!enabled)
            }
            Panel(title:"Místní USB konzole",symbol:"terminal",subtitle:"Advert a discovery aktivně vysílají přes LoRa a vyžadují potvrzení.") {
                VStack(alignment:.leading,spacing:14) {
                    Picker("Nápověda příkazů",selection:$suggestion) {Text("Vyberte příkaz").tag("");ForEach(suggestions,id:\.self){Text($0).tag($0)}}
                        .onChange(of:suggestion){_,text in if !text.isEmpty {command = text}}
                    TextField("Např. stats-core nebo get name",text:$command)
                    HStack {
                        Button("Odeslat USB příkaz…") {let text = command;command = "";model.command(text)}
                        Button("Synchronizovat hodiny…") {model.command("time \(UInt32(Date().timeIntervalSince1970))")}
                        Button("Restartovat…") {model.command("reboot")}
                    }.disabled(!enabled)
                    Text("Po timeoutu se nic neopakuje. Výpis patří pouze této relaci; citlivé příkazy a odpovědi se v historii nezobrazují.").font(.caption).foregroundStyle(.secondary)
                    ScrollView {Text(model.transcript.joined(separator:"\n\n")).font(.system(.callout,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}.frame(minHeight:220,maxHeight:440)
                }
            }
            Text("stats-radio: RSSI/SNR patří poslednímu paketu přijatému tímto repeaterem; noise floor je hlukové pozadí. USB spoj nemá RSSI ani SNR.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
