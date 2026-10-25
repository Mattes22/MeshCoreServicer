// Standalone visual QA harness. Not included in the application target.
// Fixtures are explicitly marked; no CBCentralManager is created and nothing is transmitted.
import AppKit
import SwiftUI
import MeshCoreKit

@main struct RenderPreviews {
    @MainActor static func main() async throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let output = CommandLine.arguments.dropFirst().first ?? "/private/tmp/meshcore-ui-previews"
        try FileManager.default.createDirectory(atPath:output,withIntermediateDirectories:true)
        let model = AppModel(ble:BluetoothTransport(startImmediately:false))
        let now = Date()
        let fixtureAccount = String(repeating:"5",count:64)
        var selfFrame = Data([5,0,0,0])+Data(repeating:0x55,count:32)+Data(repeating:0,count:12)
        selfFrame.appendLE(868000); selfFrame.appendLE(125000); selfFrame.append(contentsOf:[7,5]); selfFrame.append(Data("Companion A".utf8))
        model.event(try MeshCodec.decode(selfFrame))
        var device = Data([13,14,100,8,0,0,0,0])
        for (text,count) in [("24 Oct 2026",12),("Ukázková deska",40),("v1.18.0",20)] {
            var field = Data(text.utf8); field.append(Data(repeating:0,count:count-field.count)); device.append(field)
        }
        model.event(try MeshCodec.decode(device))
        try model.library.rename(fixtureAccount,alias:"Přenosný companion")
        try model.library.saveShortcut(title:"Verze uzlu",command:"ver",template:false)
        try model.library.saveShortcut(title:"Přejmenovat uzel",command:"set name",template:true)
        let repeater = Contact(key:Data(repeating:0xab,count:32),kind:2,name:"Repeater A",lastAdvert:UInt32(now.timeIntervalSince1970-600),latitude:0,longitude:0,stored:true)
        var direct = repeater; direct.outPathLength = 0
        var distant = Contact(key:Data(repeating:0xcd,count:32),kind:2,name:"Repeater B",lastAdvert:UInt32(now.timeIntervalSince1970-3600),stored:true); distant.outPathLength = 0x42
        let companion = Contact(key:Data(repeating:0xee,count:32),kind:1,name:"Companion A",stored:true)
        let room = Contact(key:Data(repeating:0xff,count:32),kind:3,name:"Komunitní room",stored:true)
        model.contacts = [direct,distant,companion,room]
        model.selectedID = direct.id
        model.initialized = true; model.adminID = direct.id
        model.verified[direct.id] = now.addingTimeInterval(-28)
        model.config = ["name":"Repeater A","lat":"0.000000","lon":"0.000000","radio":"868.000,125.000,7,5","tx":"17","repeat":"on","advert.interval":"120","flood.advert.interval":"12"]
        model.edits = model.config
        model.config.merge(["owner.info":"Vlastník - kontakt@example.invalid","dutycycle":"20.0%","af":"4","path.hash.mode":"0","flood.max":"16","flood.max.advert":"8","flood.max.unscoped":"16","loop.detect":"minimal"]) { _,new in new }
        model.edits = model.config
        model.tools.firmware = "RAK4631 Repeater v1.18.0-81dbae5"
        model.tools.board = "RAK4631"
        model.tools.clock = "13:34 - 24/10/2026 UTC"; model.tools.clockRead = now
        model.tools.useCzechProfile = true; model.tools.communityLoaded = true; model.tools.communitySnapshot = model.config
        model.tools.communityDutyKey = "dutycycle"; model.tools.communityOwner = "Vlastník - kontakt@example.invalid"
        model.tools.communitySelected = ["flood.advert.interval","advert.interval","dutycycle","path.hash.mode"]
        model.tools.telemetry = try TelemetryReport.decode(Data([1,116,1,0x72,1,103,0,185]))
        model.tools.telemetryDate = now
        model.tools.access = try AccessEntry.decode(companion.key.prefix(6)+Data([3]))
        model.tools.accessDate = now
        model.tools.regionDump = "* F\n#cz F\n#eu F"; model.tools.regionHome = "home is #cz"; model.tools.regionDefault = "default scope is #cz"
        for key in CLIValidation.keys { model.configDates[key] = now }
        model.statsDate = now.addingTimeInterval(-28)
        var stats = Data([0x74,0x0e,0,0,0x88,0xff,0x9c,0xff])
        for n: UInt32 in [12483,3150,832,189400,2600,550,10920,1563] { stats.appendLE(n) }
        stats.append(contentsOf:[0,0,22,0,15,0,24,0]); stats.appendLE(1360); stats.appendLE(2)
        model.stats = try RepeaterStatus.decode(stats)
        await model.operations.activate(account:fixtureAccount); model.operations.select(direct.id)
        for i in 0..<12 {
            var past = stats
            let battery = UInt16(3860-i*15); past[0] = UInt8(truncatingIfNeeded:battery); past[1] = UInt8(battery >> 8)
            var uptime = Data(); uptime.appendLE(UInt32(150000+i*3600)); past.replaceSubrange(20..<24,with:uptime)
            model.operations.record(try RepeaterStatus.decode(past),repeater:direct.id,date:now.addingTimeInterval(Double(i-11)*3600))
        }
        model.operations.restartRequested(repeater:direct.id); model.operations.beginChange("Rádio · vyžaduje restart",repeater:direct.id)
        try model.operations.addSnapshot(ConfigSnapshot(account:fixtureAccount,repeater:direct.id,name:"Před úpravou rádia",values:["name":"Repeater A","radio":"868.000,125.0,7,5","flood.advert.interval":"25","advert.interval":"0","path.hash.mode":"1"],readAt:["name":now.addingTimeInterval(-3600)]))
        model.console = [ConsoleLine(target:direct.name,targetID:direct.id,command:"ver",response:"RAK4631 Repeater v1.18.0-81dbae5",state:.replied),ConsoleLine(target:direct.name,targetID:direct.id,command:"get radio",response:"> 868.000,125.000,7,5",state:.replied)]
        model.history = ["get radio","ver"]
        model.observeCLI(key:direct.key,command:"get radio",reply:"> 868.000,125.000,7,5")
        model.operations.beginChange("name",repeater:direct.id,expected:"Nový název")
        model.logs = [LogLine(text:"Načteny informace companionu."),LogLine(text:"Repeater potvrdil přihlášení správce."),LogLine(text:"Repeater odpověděl na žádost o stav."),LogLine(text:"Ukázková chyba přenosu pro vizuální kontrolu.",level:.error)]
        await model.messages.activate(account:String(repeating:"5",count:64))
        let channel = try ChannelInfo(index:0,name:"Ukázkový kanál",secret:Data(repeating:0x11,count:16))
        model.messages.setChannel(channel)
        var received = Data([17,24,0,0,0,2,0]); received.appendLE(UInt32(now.timeIntervalSince1970-120)); received.append(Data("Uzel B: Je repeater dostupný?".utf8))
        if case .channelMessage(let m) = try MeshCodec.decode(received) { model.messages.receive(m) }
        var outgoing = ChatRecord(conversationID:channel.id,title:channel.name,channelIndex:0,outgoing:true,sender:"Companion A",text:"Ahoj! Repeater odpovídá, baterie má 3.70 V.",timestamp:UInt32(now.timeIntervalSince1970-60),delivery:.accepted)
        outgoing.captures = [PacketCapture(date:now.addingTimeInterval(-45),hops:1,rssi:-92,snr:3.5),PacketCapture(date:now.addingTimeInterval(-43),hops:2,rssi:-96,snr:1.25),PacketCapture(date:now.addingTimeInterval(-40),hops:2,rssi:-88,snr:6)]
        outgoing.capturedForwardings = 3; outgoing.hops = 2; outgoing.lastObservation = now.addingTimeInterval(-40)
        model.messages.appendOutgoing(outgoing); model.messages.select(channel.id)
        for (name,section,tab) in [("messages",WorkspaceSection.messages,RepeaterTab.overview),("contacts",.contacts,.overview),("repeater",.repeater,.overview),("settings",.repeater,.settings),("radio",.repeater,.radio),("console",.console,.overview),("diagnostics",.diagnostics,.overview),("connection",.connection,.overview)] {
            model.command = section == .console ? "get ra" : ""
            for dark in [false,true] {
                let root = ContentView(model:model,ble:model.ble,section:section,repeaterTab:tab)
                    .environment(\.colorScheme,dark ? .dark : .light)
                    .overlay(alignment:.topTrailing) { Text("NÁHLED · UKÁZKOVÁ DATA · BEZ BLE").font(.system(size:9,weight:.bold)).padding(8).foregroundStyle(.black).background(.yellow).padding(6) }
                try render(root,name:"\(name)-\(dark ? "dark" : "light")",output:output,dark:dark)
            }
        }
        for (name,tab,group) in [("setup",RepeaterTab.setup,RepeaterToolSection.diagnostics),("tools",.tools,.diagnostics),("network",.tools,.network),("access",.tools,.access)] {
            for dark in [false,true] {
                let root = ContentView(model:model,ble:model.ble,section:.repeater,repeaterTab:tab,repeaterToolsSection:group)
                    .environment(\.colorScheme,dark ? .dark : .light)
                    .overlay(alignment:.topTrailing) { Text("NÁHLED · UKÁZKOVÁ DATA · BEZ BLE").font(.system(size:9,weight:.bold)).padding(8).foregroundStyle(.black).background(.yellow).padding(6) }
                try render(root,name:"\(name)-\(dark ? "dark" : "light")",output:output,dark:dark)
            }
        }
        for (name,page) in [("health",OperationsTab.health),("snapshots",.snapshots),("restart-review",.restart)] {
            for dark in [false,true] {
                let root = ContentView(model:model,ble:model.ble,section:.repeater,repeaterTab:.history,operationsTab:page)
                    .environment(\.colorScheme,dark ? .dark : .light)
                    .overlay(alignment:.topTrailing) { Text("NÁHLED · UKÁZKOVÁ DATA · BEZ BLE").font(.system(size:9,weight:.bold)).padding(8).foregroundStyle(.black).background(.yellow).padding(6) }
                try render(root,name:"\(name)-\(dark ? "dark" : "light")",output:output,dark:dark)
            }
        }
        for dark in [false,true] {
            let flag = Text("NÁHLED · UKÁZKOVÁ DATA · BEZ BLE").font(.system(size:9,weight:.bold)).padding(8).foregroundStyle(.black).background(.yellow)
            try render(DiagnosticReportView(model:model).environment(\.colorScheme,dark ? .dark : .light).overlay(alignment:.bottomTrailing) { flag },name:"report-\(dark ? "dark" : "light")",output:output,dark:dark,size:NSSize(width:740,height:650))
            try render(HardwareVerificationView(model:model,library:model.library).environment(\.colorScheme,dark ? .dark : .light).overlay(alignment:.bottomTrailing) { flag },name:"compatibility-\(dark ? "dark" : "light")",output:output,dark:dark,size:NSSize(width:740,height:650))
            try render(ConsoleShortcutsView(model:model,library:model.library,selected:model.library.shortcuts.last?.id).environment(\.colorScheme,dark ? .dark : .light).overlay(alignment:.bottomTrailing) { flag },name:"shortcuts-\(dark ? "dark" : "light")",output:output,dark:dark,size:NSSize(width:620,height:620))
        }
        for tab in [AppSettingsTab.general,.console] {
            for dark in [false,true] {
                let root = AppSettingsView(model:model,preferences:model.preferences,notifications:model.notifications,tab:tab).environment(\.colorScheme,dark ? .dark : .light)
                    .overlay(alignment:.bottomTrailing) { Text("NÁHLED · BEZ BLE A SYSTÉMOVÝCH OZNÁMENÍ").font(.system(size:9,weight:.bold)).padding(8).foregroundStyle(.black).background(.yellow).padding(6) }
                try render(root,name:"preferences\(tab == .console ? "-console" : "")-\(dark ? "dark" : "light")",output:output,dark:dark,size:NSSize(width:600,height:640))
            }
        }
    }
    @MainActor static func render<V: View>(_ view: V,name: String,output: String,dark: Bool,size: NSSize = NSSize(width:1240,height:850)) throws {
        let host = NSHostingView(rootView:view.frame(width:size.width,height:size.height))
        host.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
        let window = NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:[.borderless],backing:.buffered,defer:false)
        window.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(origin:.zero,size:size)
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until:Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds) else { fatalError("Cannot create bitmap") }
        host.cacheDisplay(in:host.bounds,to:bitmap)
        guard let png = bitmap.representation(using:.png,properties:[:]) else { fatalError("Cannot encode PNG") }
        try png.write(to:URL(fileURLWithPath:output).appendingPathComponent(name+".png"))
        window.close()
        print(name)
    }
}
