import XCTest
@testable import MeshCoreKit

final class ProtocolTests: XCTestCase {
    let key = Data(0..<32)
    func testNordicUARTAndBLEBoundaries() throws {
        XCTAssertEqual(MeshCodec.serviceUUID,"6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
        let frame = try MeshCodec.cli(key:key, command:"get radio", timestamp:0x12345678)
        XCTAssertEqual(Array(frame.prefix(13)),[2,1,0,0x78,0x56,0x34,0x12,0,1,2,3,4,5])
        XCTAssertEqual(try MeshCodec.bleFrame(frame),frame)
        XCTAssertThrowsError(try MeshCodec.bleFrame(frame, maximumWriteLength:20))
        XCTAssertThrowsError(try MeshCodec.bleFrame(Data(repeating:0,count:177)))
        XCTAssertThrowsError(try MeshCodec.bleFrame(Data()))
    }
    func testLoginUsesFullKeyAndByteLimit() throws {
        XCTAssertEqual(try MeshCodec.login(key:key,password:"heslo"),Data([26])+key+Data("heslo".utf8))
        XCTAssertThrowsError(try MeshCodec.login(key:key,password:String(repeating:"ě",count:8)))
        XCTAssertThrowsError(try MeshCodec.login(key:Data([0]),password:"heslo"))
    }
    func testCLIRejectsInjectionAndUnicodeOverflow() {
        XCTAssertThrowsError(try MeshCodec.cli(key:key,command:"get name\nreboot",timestamp:0))
        XCTAssertThrowsError(try MeshCodec.cli(key:key,command:String(repeating:"ě",count:67),timestamp:0))
    }
    func testContactOffsetsAndSignedCoordinates() throws {
        var d = Data([3])+key+Data([2,0,255])+Data(repeating:0,count:64)
        var name = Data("Repeater".utf8); name.append(Data(repeating:0,count:32-name.count)); d.append(name)
        d.appendLE(123); d.appendLE(UInt32(bitPattern:-12_500_000)); d.appendLE(14_123_456); d.appendLE(789)
        guard case .contact(let c) = try MeshCodec.decode(d) else { return XCTFail() }
        XCTAssertEqual(c.key,key); XCTAssertEqual(c.name,"Repeater"); XCTAssertEqual(c.latitude,-12.5); XCTAssertEqual(c.longitude,14.123456); XCTAssertTrue(c.stored)
        d[0] = 0x8a
        guard case .contact(let advert) = try MeshCodec.decode(d) else { return XCTFail() }
        XCTAssertFalse(advert.stored)
        for length in 1..<d.count { XCTAssertThrowsError(try MeshCodec.decode(d.prefix(length)),"length \(length)") }
    }
    func testV3CLISignedSNR() throws {
        var d = Data([16,UInt8(bitPattern:-18),0,0])+key.prefix(6)+Data([255,1]); d.appendLE(1234); d.append(Data("OK".utf8))
        guard case .message(let m) = try MeshCodec.decode(d) else { return XCTFail() }
        XCTAssertEqual(m.prefix,key.prefix(6)); XCTAssertEqual(m.snr,-4.5); XCTAssertEqual(m.text,"OK"); XCTAssertEqual(m.type,1)
        for length in 1..<16 { XCTAssertThrowsError(try MeshCodec.decode(d.prefix(length))) }
    }
    func testSelfInfoAndDeviceInfoDoNotExposePIN() throws {
        var d = Data([5])+Data(repeating:0,count:47); d.appendLE(869432); d.appendLE(62500); d.append(contentsOf:[7,5]); d.append(Data("Companion A".utf8))
        guard case .selfInfo(let s) = try MeshCodec.decode(d) else { return XCTFail() }
        XCTAssertEqual(s.name,"Companion A"); XCTAssertEqual(s.frequency,869.432); XCTAssertEqual(s.bandwidth,62.5); XCTAssertEqual(s.sf,7)
        var info = Data([13,14,100,8,0x40,0xe2,1,0])
        for (text,count) in [("23 Oct 2026",12),("Heltec T114",40),("v1.18.0",20)] { var v=Data(text.utf8); v.append(Data(repeating:0,count:count-v.count)); info.append(v) }
        guard case .deviceInfo(let i) = try MeshCodec.decode(info) else { return XCTFail() }
        XCTAssertEqual(i.protocolVersion,14); XCTAssertEqual(i.model,"Heltec T114"); XCTAssertEqual(i.version,"v1.18.0")
    }
    func testDiscoveryTagAndLinkDirection() throws {
        XCTAssertEqual(MeshCodec.discover(tag:0x12345678),Data([55,0x80,4,0x78,0x56,0x34,0x12]))
        var d = Data([0x8e,20,UInt8(bitPattern:-101),0,0x92,UInt8(bitPattern:-8)]); d.appendLE(77); d.append(key)
        guard case .discovery(let result) = try MeshCodec.decode(d) else { return XCTFail() }
        XCTAssertEqual(result.tag,77); XCTAssertEqual(result.companionRSSI,-101); XCTAssertEqual(result.companionSNR,5); XCTAssertEqual(result.repeaterSNR,-2)
    }
    func testStatusLayoutAndNoiseIsSeparate() throws {
        var d = Data([0x74,0x0e,2,0,0x88,0xff,0x9c,0xff]) // 3700mV, queue2, noise -120, RSSI -100
        for n: UInt32 in [10,20,30,40,50,60,70,80] { d.appendLE(n) }
        d.append(contentsOf:[1,0,0xf6,0xff,3,0,4,0]); d.appendLE(90); d.appendLE(100)
        let s = try RepeaterStatus.decode(d)
        XCTAssertEqual(s.battery,3700); XCTAssertEqual(s.noiseFloor,-120); XCTAssertEqual(s.lastRSSI,-100); XCTAssertEqual(s.lastSNR,-2.5); XCTAssertEqual(s.uptime,40); XCTAssertEqual(s.rxAirtime,90); XCTAssertEqual(s.receiveErrors,100)
        XCTAssertThrowsError(try RepeaterStatus.decode(d.prefix(47)))
        let legacy = try RepeaterStatus.decode(d.prefix(48)); XCTAssertNil(legacy.rxAirtime)
    }
    func testValidationAndSensitiveCommands() throws {
        XCTAssertTrue(CLIValidation.sensitive("get prv.key")); XCTAssertTrue(CLIValidation.sensitive("password abc"))
        XCTAssertTrue(CLIValidation.needsRadioWarning("set radio 869.432,62.5,7,5"))
        XCTAssertTrue(CLIValidation.needsRestartConfirmation("reboot"))
        XCTAssertEqual(try CLIValidation.validate(key:"radio",value:"869.432,62.5,7,5"),"869.432,62.5,7,5")
        XCTAssertThrowsError(try CLIValidation.validate(key:"lat",value:"NaN"))
        XCTAssertThrowsError(try CLIValidation.validate(key:"advert.interval",value:"2"))
        XCTAssertThrowsError(try CLIValidation.validate(key:"advert.interval",value:"61"))
        XCTAssertTrue(CLIValidation.isErrorReply("Unknown command"))
    }
}

@MainActor final class FakeTransport: MeshTransport {
    var onFrame: ((Data)->Void)?
    var onDisconnect: (()->Void)?
    var sent: [Data] = []
    var completionError: Error?
    var handle: ((Data)->Void)?
    func write(_ frame: Data) async throws { sent.append(frame); handle?(frame); if let completionError { throw completionError } }
    func emit(_ data: Data) { onFrame?(data) }
}
final class SessionTests: XCTestCase {
    @MainActor func testInitializationOnlyReadsLocalInformation() async throws {
        let t = FakeTransport(), s = MeshSession(transport:t)
        t.handle = { frame in
            switch frame[0] {
            case 22: t.emit(Data([13,2]))
            case 1: var d=Data([5])+Data(repeating:0,count:47); d.appendLE(869432); d.appendLE(62500); d.append(contentsOf:[7,5]); t.emit(d)
            case 20:t.emit(Data([12,0x74,0x0e]))
            default: XCTFail("Unexpected transmission")
            }
        }
        try await s.initialize(); XCTAssertEqual(t.sent.map { $0[0] },[22,1,20])
    }
    @MainActor func testContactStreamDoesNotFinishAtStart() async throws {
        let t = FakeTransport(), s = MeshSession(transport:t)
        t.handle = { _ in t.emit(Data([2,0,0,0,0])); t.emit(Data([0x83])); t.emit(Data([4,0,0,0,0])) }
        try await s.contacts(); XCTAssertEqual(t.sent,[Data([4])])
    }
    @MainActor func testLoginIgnoresOtherNodeAndAcceptsEarlyPush() async throws {
        let t = FakeTransport(), s = MeshSession(transport:t), key=Data(0..<32)
        t.handle = { _ in
            t.emit(Data([0x85,1])+Data(repeating:99,count:6))
            t.emit(Data([0x85,1])+key.prefix(6)) // may arrive before SENT
            t.emit(Data([6,0,0,0,0,0,0,0,0,0]))
        }
        let permissions = try await s.login(key:key,password:"test")
        XCTAssertEqual(permissions,1)
    }
    @MainActor func testLoginFailure() async throws {
        let t = FakeTransport(), s = MeshSession(transport:t), key=Data(0..<32)
        t.handle = { _ in t.emit(Data([6,0,0,0,0,0,0,0,0,0])); t.emit(Data([0x86,0])+key.prefix(6)) }
        do { _ = try await s.login(key:key,password:"wrong"); XCTFail() } catch { XCTAssertTrue(error.localizedDescription.contains("odmítl")) }
    }
    @MainActor func testCLIIsPolledAndOnlyMatchesCorrectSenderAndType() async throws {
        let t = FakeTransport(), s = MeshSession(transport:t), key=Data(0..<32)
        var commandSent=false
        func msg(_ prefix: Data,_ type: UInt8,_ time: UInt32,_ text: String) -> Data { var d=Data([7])+prefix+Data([255,type]); d.appendLE(time); return d+Data(text.utf8) }
        t.handle = { frame in
            if frame[0] == 2 { commandSent=true; t.emit(Data([6,0,0,0,0,0,0,0,0,0])); t.emit(msg(Data(repeating:99,count:6),1,1,"WRONG")); t.emit(msg(key.prefix(6),0,2,"CHAT")) }
            if frame[0] == 10 {
                if commandSent { t.emit(msg(key.prefix(6),1,3,"OK")); commandSent=false } else { t.emit(Data([10])) }
            }
        }
        let result = try await s.cli(key:key,command:"get name")
        XCTAssertEqual(result,"OK"); XCTAssertEqual(t.sent.first,Data([10])); XCTAssertEqual(t.sent.filter { $0[0] == 2 }.count,1)
    }
    @MainActor func testErrorsAndDisconnectDoNotLeaveContinuationHanging() async throws {
        let t = FakeTransport(), s = MeshSession(transport:t)
        t.handle = { _ in t.emit(Data([1,2])) }
        do { try await s.contacts(); XCTFail() } catch { XCTAssertTrue(error.localizedDescription.contains("kód 2")) }
        t.handle = { _ in t.onDisconnect?() }
        do { try await s.contacts(); XCTFail() } catch { XCTAssertTrue(error.localizedDescription.contains("připojen")) }
    }
    @MainActor func testMalformedFramesCannotSatisfyRequest() async throws {
        let t = FakeTransport(), s = MeshSession(transport:t)
        var malformed=0; s.onMalformed = { malformed += 1 }
        t.handle = { _ in t.emit(Data([4])); t.emit(Data([4,0,0,0,0])) }
        try await s.contacts(); XCTAssertEqual(malformed,1)
    }
    @MainActor func testTimeoutPoisonsSessionUntilDisconnect() async throws {
        let t = FakeTransport(), s = MeshSession(transport:t, localTimeout:0.02)
        do { _ = try await s.login(key:Data(0..<32),password:"test"); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("Vypršel")) }
        do { try await s.contacts(); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("předchozím timeoutu")) }
        XCTAssertEqual(t.sent.count,1)
        t.onDisconnect?()
        t.handle = { _ in t.emit(Data([4,0,0,0,0])) }
        try await s.contacts()
    }
    @MainActor func testDuplicateMessageStillCompletesLocalPoll() async throws {
        let t = FakeTransport(), s = MeshSession(transport:t), key=Data(0..<32)
        var message = Data([7])+key.prefix(6)+Data([255,1]); message.appendLE(42); message.append(Data("old".utf8))
        var polls=0
        t.handle = { f in
            if f[0] == 10 { polls += 1; if polls <= 2 { t.emit(message) } else { t.emit(Data([10])) } }
            if f[0] == 2 { t.emit(Data([6,0,0,0,0,0,0,0,0,0])) }
        }
        _ = try await s.cli(key:key,command:"reboot",noReply:true)
        XCTAssertEqual(polls,3)
    }
    @MainActor func testWriteErrorAfterReplyCannotBeReportedAsSuccess() async throws {
        let t = FakeTransport(), s = MeshSession(transport:t)
        t.handle = { _ in t.emit(Data([4,0,0,0,0])) }
        t.completionError = MeshError.disconnected
        do { try await s.contacts(); XCTFail() } catch { XCTAssertTrue(error.localizedDescription.contains("připojen")) }
    }
    @MainActor func testDisconnectDuringWriteDoesNotPoisonNewConnection() async throws {
        let t = FakeTransport(), s = MeshSession(transport:t)
        t.completionError = MeshError.disconnected
        t.handle = { _ in t.onDisconnect?() }
        do { try await s.contacts(); XCTFail() } catch { }
        await Task.yield()
        t.completionError = nil
        t.handle = { _ in t.emit(Data([4,0,0,0,0])) }
        try await s.contacts()
    }
    @MainActor func testConcurrentOperationsAreRejected() async throws {
        let t = FakeTransport(), s = MeshSession(transport:t)
        let first = Task { try await s.contacts() }
        while t.sent.isEmpty { await Task.yield() }
        do { try await s.contacts(); XCTFail() } catch { XCTAssertTrue(error.localizedDescription.contains("jiný")) }
        t.emit(Data([4,0,0,0,0])); try await first.value
    }
}
