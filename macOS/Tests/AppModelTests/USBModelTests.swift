import XCTest
import Darwin
import MeshCoreKit
@testable import MeshCoreServicer

private final class USBPseudoTerminal: @unchecked Sendable {
    let master: Int32
    let slave: Int32
    let path: String
    init() throws {
        var a: Int32 = -1,b: Int32 = -1,name = [CChar](repeating:0,count:1024)
        guard openpty(&a,&b,&name,nil,nil) == 0 else {throw MeshError.invalid("test pseudo terminal")}
        master = a;slave = b;path = String(cString:name)
    }
    deinit {Darwin.close(master);Darwin.close(slave)}
    func read(_ required: Int) throws -> [UInt8] {
        var bytes = [UInt8]()
        let end = DispatchTime.now().uptimeNanoseconds+3_000_000_000
        while bytes.count < required {
            if DispatchTime.now().uptimeNanoseconds > end {throw MeshError.timeout}
            var item = pollfd(fd:master,events:Int16(POLLIN),revents:0)
            if poll(&item,1,50) <= 0 {continue}
            var chunk = [UInt8](repeating:0,count:required-bytes.count)
            let count = Darwin.read(master,&chunk,chunk.count)
            guard count > 0 else {throw MeshError.disconnected}
            bytes += chunk.prefix(count)
        }
        return bytes
    }
    func write(_ bytes: Data) throws {
        try bytes.withUnsafeBytes {raw in
            guard Darwin.write(master,raw.baseAddress,raw.count) == raw.count else {throw MeshError.disconnected}
        }
    }
}
@MainActor final class USBModelTests: XCTestCase {
    private func until(_ condition: ()->Bool) async throws {
        for _ in 0..<3000 {if condition(){return};try await Task.sleep(nanoseconds:1_000_000)}
        throw MeshError.timeout
    }
    func testUSBCompanionActivatesExistingApplicationWithoutRadio() async throws {
        let tty = try USBPseudoTerminal(), model = AppModel(ble:BluetoothTransport(startImmediately:false))
        let server = Task.detached { () throws -> [UInt8] in
            var codes = [UInt8]()
            for _ in 0..<4 {
                let header = try tty.read(3);guard header[0] == 60 else {throw MeshError.invalid("test frame")}
                let payload = try tty.read(Int(header[1]) | Int(header[2]) << 8)
                let code = payload[0];codes.append(code)
                var reply: Data
                switch code {
                case 22: reply = Data([13,2])
                case 1:
                    reply = Data([5,0,0,0])+Data(repeating:0xab,count:32)+Data(repeating:0,count:12)
                    reply.appendLE(868000);reply.appendLE(125000);reply.append(contentsOf:[7,5]);reply.append(Data("USB test".utf8))
                case 20: reply = Data([12,0,16])
                case 10: reply = Data([10])
                default: throw MeshError.invalid("unexpected radio transmission in test")
                }
                try tty.write(Data([62,UInt8(reply.count),0])+reply)
            }
            return codes
        }
        model.connectUSB(tty.path,mode:.companion)
        try await until {model.initialized && !model.busy && model.messageSyncTask == nil}
        let codes = try await server.value
        XCTAssertEqual(codes,[22,1,20,10]);XCTAssertTrue(model.linkReady);XCTAssertFalse(model.ble.ready)
        XCTAssertEqual(model.selfInfo?.name,"USB test");XCTAssertFalse(model.monitoring);XCTAssertFalse(model.admin)
        model.disconnectAll();XCTAssertFalse(model.initialized);XCTAssertFalse(model.usb.ready)
    }
    func testUSBRepeaterInitializesLocalModelWithoutCompanionOrLoRa() async throws {
        let tty = try USBPseudoTerminal(), app = AppModel(ble:BluetoothTransport(startImmediately:false))
        let server = Task.detached { () throws -> [String] in
            var commands = [String]()
            for _ in 0..<3 {
                var bytes = [UInt8]()
                while bytes.last != 13 {bytes += try tty.read(1)}
                let text = String(decoding:bytes,as:UTF8.self),tag = String(text.prefix(3)),command = String(text.dropFirst(3).dropLast())
                commands.append(command)
                let reply = command == "ver" ? "v1.18.0" : command == "board" ? "RAK4631" : "> USB repeater"
                try tty.write(Data(("  -> "+tag+reply+"\r\n").utf8))
            }
            return commands
        }
        app.connectUSB(tty.path,mode:.repeater)
        try await until {!app.busy && app.usb.ready}
        let commands = try await server.value
        XCTAssertEqual(commands,["ver","board","get name"]);XCTAssertTrue(app.directUSB)
        XCTAssertEqual(app.usbRepeater.name,"USB repeater");XCTAssertFalse(app.initialized);XCTAssertFalse(app.admin);XCTAssertTrue(app.contacts.isEmpty)
        app.disconnectAll();XCTAssertFalse(app.usb.ready)
    }
    func testUSBFailureExportContainsOnlyAllowedEvents() async throws {
        let model = AppModel(ble:BluetoothTransport(startImmediately:false))
        model.connectUSB("/dev/never-existing-private-port",mode:.repeater)
        try await until {!model.busy}
        let report = DiagnosticReport.render(model.reportInput())
        XCTAssertTrue(report.contains("openFailed"));XCTAssertFalse(report.contains("never-existing-private-port"));XCTAssertFalse(model.usb.ready)
    }
}
