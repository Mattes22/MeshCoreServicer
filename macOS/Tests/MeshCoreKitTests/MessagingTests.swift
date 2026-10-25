import XCTest
@testable import MeshCoreKit

final class MessagingTests: XCTestCase {
    private func hex(_ text: String) -> Data { Data(stride(from:0,to:text.count,by:2).map { i in UInt8(text.dropFirst(i).prefix(2),radix:16)! }) }
    func testPrivateAndChannelEncodersUseDifferentTypesAndByteLimits() throws {
        let key = Data(0..<32)
        XCTAssertEqual(try MeshMessaging.direct(key:key,text:"Ahoj",timestamp:42),Data([2,0,0,42,0,0,0,0,1,2,3,4,5])+Data("Ahoj".utf8))
        XCTAssertEqual(try MeshMessaging.channel(index:2,text:"Ahoj",sender:"Ada",timestamp:42),Data([3,0,2,42,0,0,0])+Data("Ahoj".utf8))
        XCTAssertThrowsError(try MeshMessaging.direct(key:key,text:String(repeating:"ě",count:67),timestamp:0))
        XCTAssertThrowsError(try MeshMessaging.direct(key:key,text:"a\0b",timestamp:0))
        XCTAssertEqual(MeshMessaging.channelLimit(sender:String(repeating:"x",count:31)),127)
        XCTAssertThrowsError(try MeshMessaging.channel(index:0,text:String(repeating:"x",count:128),sender:String(repeating:"x",count:31),timestamp:0))
    }
    func testChannelV3PreservesPackedHopCountAndSignedSNR() throws {
        var d = Data([17,0xf4,0,0,2,0x43,0]); d.appendLE(42); d.append(Data("Ada: Ahoj".utf8))
        guard case .channelMessage(let m) = try MeshCodec.decode(d) else { return XCTFail() }
        XCTAssertEqual(m.hops,3); XCTAssertEqual(m.pathLength,0x43); XCTAssertEqual(m.index,2); XCTAssertEqual(m.snr,-3); XCTAssertEqual(m.text,"Ada: Ahoj")
        for length in 1..<11 { XCTAssertThrowsError(try MeshCodec.decode(d.prefix(length))) }
        var legacy = Data([8,0,255,0]); legacy.appendLE(5); legacy.append(65)
        guard case .channelMessage(let old) = try MeshCodec.decode(legacy) else { return XCTFail() }
        XCTAssertNil(old.hops); XCTAssertNil(old.snr)
    }
    func testSignedMessageKeepsAuthorPrefixSeparateFromText() throws {
        var d = Data([7])+Data(repeating:1,count:6)+Data([255,2]); d.appendLE(42); d.append(contentsOf:[2,3,4,5]); d.append(Data("Hello".utf8))
        guard case .message(let m) = try MeshCodec.decode(d) else { return XCTFail() }
        XCTAssertEqual(m.senderPrefix,Data([2,3,4,5])); XCTAssertEqual(m.text,"Hello")
    }
    func testACKAndSentAreNotTheSameConfirmation() throws {
        var d = Data([6,1]); d.appendLE(0x12345678); d.appendLE(2500)
        guard case .sent(let receipt) = try MeshCodec.decode(d) else { return XCTFail() }
        XCTAssertEqual(receipt.acknowledgement,0x12345678); XCTAssertEqual(receipt.timeout,2500); XCTAssertTrue(receipt.flood)
        var ack = Data([0x82]); ack.appendLE(0x12345678); ack.appendLE(930)
        XCTAssertEqual(try MeshCodec.decode(ack),.acknowledgement(code:0x12345678,roundTrip:930))
        XCTAssertThrowsError(try MeshCodec.decode(ack.prefix(5)))
    }
    func testPacketFingerprintMatchesIndependentOpenSSLAESAndHMACFixture() throws {
        let c = try ChannelInfo(index:0,name:"Test",secret:Data(repeating:0,count:16))
        let expected = "c4594b00fe3f0f7937581583c60f77a5fc9f09946c614b55bed0bdecd627a453"
        XCTAssertEqual(try c.packetFingerprint(timestamp:42,wireText:"Ada: test"),expected)
        let payload = hex("37b73f19af5f8482367bdd518ba3083a1d70bc")
        let first = try GroupObservation.decode(raw:Data([0x15,1,0xaa])+payload,rssi:-90,snr:4)
        let second = try GroupObservation.decode(raw:Data([0x14,1,0,2,0,0x42,1,2,3,4])+payload,rssi:-80,snr:6)
        XCTAssertEqual(first?.fingerprint,expected); XCTAssertEqual(second?.fingerprint,expected)
        XCTAssertEqual(first?.hops,1); XCTAssertEqual(second?.hops,2)
        XCTAssertNotEqual(try c.packetFingerprint(timestamp:43,wireText:"Ada: test"),expected)
        XCTAssertThrowsError(try GroupObservation.decode(raw:Data([0x15,0xc1])+payload,rssi:0,snr:0))
    }
    func testChannelInfoHasNoSecretInDescriptionAndDetectsEmptySlots() throws {
        let c = try ChannelInfo(index:1,name:"Test",secret:Data(repeating:0xab,count:16))
        XCTAssertFalse(c.description.contains("abab")); XCTAssertTrue(c.configured)
        XCTAssertFalse(try ChannelInfo(index:0,name:"",secret:Data(repeating:0,count:16)).configured)
        var d = Data([18,1]); var name = Data("Test".utf8); name.append(Data(repeating:0,count:28)); d.append(name); d.append(Data(repeating:0xab,count:16))
        guard case .channelInfo(let parsed) = try MeshCodec.decode(d) else { return XCTFail() }
        XCTAssertEqual(parsed,c); XCTAssertThrowsError(try MeshCodec.decode(d.prefix(49)))
    }
    @MainActor func testSyncDeliversChatAndChannelWithoutTreatingThemAsCLI() async throws {
        let t = FakeTransport(), session = MeshSession(transport:t)
        var received: [Frame] = [], count = 0
        session.onEvent = { received.append($0) }
        t.handle = { frame in
            XCTAssertEqual(frame,Data([10])); count += 1
            if count == 1 { var d=Data([7])+Data(repeating:1,count:6)+Data([255,0]); d.appendLE(1); d.append(Data("DM".utf8)); t.emit(d) }
            else if count == 2 { var d=Data([8,0,1,0]); d.appendLE(2); d.append(Data("Ada: channel".utf8)); t.emit(d) }
            else { t.emit(Data([10])) }
        }
        try await session.syncMessages()
        XCTAssertEqual(received.count,3); XCTAssertEqual(t.sent.count,3)
    }
}
