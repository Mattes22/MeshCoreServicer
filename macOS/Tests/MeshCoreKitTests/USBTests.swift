import XCTest
import Darwin
@testable import MeshCoreKit

@MainActor private final class USBFake: USBByteConnection {
    var ready = true
    var onBytes: ((Data)->Void)?
    var onClosed: (()->Void)?
    var sent: [Data] = []
    func writeBytes(_ bytes: Data) async throws {sent.append(bytes)}
    func emit(_ text: String) {onBytes?(Data(text.utf8))}
}
@MainActor private final class USBTimer {
    var continuation: CheckedContinuation<Void,Error>?
    func wait(_ _: UInt64) async throws {try await withCheckedThrowingContinuation {continuation = $0}}
    func fire() {continuation?.resume();continuation = nil}
}
@MainActor final class USBTests: XCTestCase {
    private func until(_ condition: ()->Bool) async throws {
        for _ in 0..<10000 {if condition(){return};await Task.yield()}
        throw MeshError.timeout
    }
    func testCompanionEnvelopeUsesOfficialDirectionAndBounds() throws {
        XCTAssertEqual(try USBFrameDecoder.encode(Data([22,3])),Data([60,2,0,22,3]))
        XCTAssertThrowsError(try USBFrameDecoder.encode(Data()))
        XCTAssertThrowsError(try USBFrameDecoder.encode(Data(repeating:1,count:177)))
    }
    func testEverySplitMultipleFramesAndPayloadMarkers() throws {
        let bytes: [UInt8] = [99,0,62,4,0,62,60,0,255,62,1,0,10]
        for split in 0...bytes.count {
            var parser = USBFrameDecoder()
            var result = try parser.feed(Data(bytes.prefix(split)))
            result += try parser.feed(Data(bytes.dropFirst(split)))
            XCTAssertEqual(result,[Data([62,60,0,255]),Data([10])])
        }
    }
    func testMalformedLengthFailsClosed() throws {
        for count in [0,177,65535] {var parser = USBFrameDecoder();XCTAssertThrowsError(try parser.feed(Data([62,UInt8(count&255),UInt8(count>>8)])))}
    }
    func testSplitUnicodeAndBoundedLines() throws {
        var parser = USBLineDecoder(), result = [String]()
        for byte in Data("  -> AA|Příliš žluťoučký\r\n".utf8) {result += try parser.feed(Data([byte]))}
        XCTAssertEqual(result,["  -> AA|Příliš žluťoučký"])
        XCTAssertThrowsError(try parser.feed(Data(repeating:65,count:2049)))
        var invalid = USBLineDecoder();XCTAssertThrowsError(try invalid.feed(Data([255,10])))
    }
    func testInjectionPrivateDumpsAndTruncationAreRejected() throws {
        try USBRepeaterSession.validate(String(repeating:"x",count:154))
        try USBRepeaterSession.validate("set owner.info Monkey | public contact")
        for command in ["ver\rreboot","ver\nreboot","AA|reboot","get prv.key","get acl","erase","log","region load",String(repeating:"ě",count:78)] {XCTAssertThrowsError(try USBRepeaterSession.validate(command))}
    }
    func testCLIRequiresTaggedReplyAndIgnoresEcho() async throws {
        let port = USBFake()
        let session = USBRepeaterSession(port:port)
        let request = Task {try await session.command("get name")}
        try await until {!port.sent.isEmpty}
        let tag = String(decoding:port.sent[0].prefix(3),as:UTF8.self)
        port.emit(tag+"get name\r\n  -> XX|noise\r\nstartup\n")
        port.emit("  -> "+tag+"> Žluťoučký\r\n")
        let response = try await request.value
        XCTAssertEqual(response,"> Žluťoučký")
    }
    func testConcurrentCommandIsRejectedWithoutQueue() async throws {
        let port = USBFake()
        let cli = USBRepeaterSession(port:port)
        let first = Task {try await cli.command("ver")}
        try await until {!port.sent.isEmpty}
        do {_ = try await cli.command("board");XCTFail()} catch {}
        XCTAssertEqual(port.sent.count,1);port.ready = false;port.onClosed?()
        do {_ = try await first.value;XCTFail()} catch {}
    }
    func testControlledTimeoutPoisonsSessionAndNeverRetries() async throws {
        let port = USBFake(), timer = USBTimer()
        let cli = USBRepeaterSession(port:port,sleep:timer.wait)
        let first = Task {try await cli.command("ver")}
        try await until {timer.continuation != nil}
        timer.fire()
        do {_ = try await first.value;XCTFail()} catch {}
        XCTAssertTrue(cli.requiresReconnect)
        do {_ = try await cli.command("board");XCTFail()} catch {}
        XCTAssertEqual(port.sent.count,1)
    }
    func testReconnectUsesNewTagAndRejectsLateReply() async throws {
        let port = USBFake()
        let session = USBRepeaterSession(port:port)
        let first = Task {try await session.command("ver")}
        try await until {!port.sent.isEmpty}
        let old = String(decoding:port.sent[0].prefix(3),as:UTF8.self)
        session.reset();do {_ = try await first.value;XCTFail()} catch {}
        let next = Task {try await session.command("board")}
        try await until {port.sent.count == 2}
        let current = String(decoding:port.sent[1].prefix(3),as:UTF8.self)
        XCTAssertNotEqual(old,current)
        port.emit("  -> "+old+"late\n");port.emit("  -> "+current+"RAK\n")
        let reply = try await next.value;XCTAssertEqual(reply,"RAK")
    }
    func testNoReplyRestartIsExplicitlyUnconfirmed() async throws {
        let port = USBFake()
        let session = USBRepeaterSession(port:port)
        let result = try await session.command("reboot")
        XCTAssertTrue(result.contains("nemá potvrzující"));XCTAssertTrue(session.requiresReconnect);XCTAssertEqual(port.sent.count,1)
    }
    func testNativeSerialTransportWithPseudoTerminalOnly() async throws {
        var master: Int32 = -1,slave: Int32 = -1
        var name = [CChar](repeating:0,count:1024)
        XCTAssertEqual(openpty(&master,&slave,&name,nil,nil),0)
        guard master >= 0,slave >= 0 else {return}
        defer {Darwin.close(master);Darwin.close(slave)}
        let path = String(cString:name), port = USBTransport()
        try await port.open(path,mode:.companion)
        defer {port.disconnect()}
        try await port.write(Data([22,3]))
        var pollItem = pollfd(fd:master,events:Int16(POLLIN),revents:0)
        XCTAssertEqual(poll(&pollItem,1,1000),1)
        var bytes = [UInt8](repeating:0,count:128)
        let count = Darwin.read(master,&bytes,bytes.count)
        XCTAssertEqual(Array(bytes.prefix(count)),[60,2,0,22,3])
        var received = [Data]();port.onFrame = {received.append($0)}
        let response: [UInt8] = [62,1,0,10]
        _ = response.withUnsafeBytes {Darwin.write(master,$0.baseAddress,$0.count)}
        try await until {!received.isEmpty};XCTAssertEqual(received,[Data([10])])
    }
}
