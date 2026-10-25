import XCTest
@testable import MeshCoreKit

final class RepeaterToolsTests: XCTestCase {
    func testCommunityProfileUsesOneDutySettingAndNoRadioOrIdentity() {
        let modern = CommunitySetting.recommended(dutyKey:"dutycycle",owner:"Jan - jan@example.net")
        XCTAssertEqual(Dictionary(uniqueKeysWithValues:modern.map{($0.key,$0.target)}),["flood.advert.interval":"25","advert.interval":"0","dutycycle":"10","path.hash.mode":"1","owner.info":"Jan - jan@example.net"])
        let legacy = CommunitySetting.recommended(dutyKey:"af",owner:"")
        XCTAssertEqual(legacy.first(where:{$0.key == "af"})?.target,"9")
        XCTAssertFalse(legacy.contains(where:{$0.key == "dutycycle"}))
        XCTAssertFalse(CommunitySetting.recommended(dutyKey:nil,owner:"").contains(where:{["dutycycle","af"].contains($0.key)}))
    }
    func testValidationUsesByteLimitsAndCanonicalDutyCycle() throws {
        XCTAssertEqual(try CLIValidation.validate(key:"owner.info",value:String(repeating:"ž",count:59)).utf8.count,118)
        XCTAssertThrowsError(try CLIValidation.validate(key:"owner.info",value:String(repeating:"ž",count:60)))
        XCTAssertThrowsError(try CLIValidation.validate(key:"owner.info",value:"Jan\nreboot"))
        XCTAssertEqual(try CLIValidation.validate(key:"dutycycle",value:"10.0%"),"10.0")
        XCTAssertThrowsError(try CLIValidation.validate(key:"dutycycle",value:"0"))
        XCTAssertThrowsError(try CLIValidation.validate(key:"af",value:"10"))
        XCTAssertThrowsError(try CLIValidation.validate(key:"path.hash.mode",value:"3"))
        XCTAssertEqual(try CLIValidation.validate(key:"path.hash.mode",value:"1"),"1")
        XCTAssertTrue(MeshPresentation.sameValue(key:"dutycycle","10.0%","10"))
        XCTAssertFalse(MeshPresentation.sameValue(key:"dutycycle","11.0%","10"))
    }
    func testACLParsesRolesAndCipherPaddingWithoutInventedEntries() throws {
        let key = Data([1,2,3,4,5,6])
        let entries = try AccessEntry.decode(key+Data([0x83])+Data(repeating:0,count:5))
        XCTAssertEqual(entries.count,1); XCTAssertEqual(entries[0].prefix,key)
        XCTAssertEqual(entries[0].permissions,0x83); XCTAssertEqual(entries[0].role,"Správce")
        XCTAssertTrue(try AccessEntry.decode(Data(repeating:0,count:12)).isEmpty)
        XCTAssertThrowsError(try AccessEntry.decode(Data([1,2,3])))
        XCTAssertThrowsError(try AccessEntry.decode(Data(repeating:0,count:16)))
    }
    func testNeighbourRequestAndPageWithFullKeysSignedSNRAndPadding() throws {
        XCTAssertEqual(NeighbourPage.request(offset:0x1234,nonce:0xabcdef01),Data([6,0,3,0x34,0x12,0,32,1,0xef,0xcd,0xab]))
        var raw = Data([4,0,1,0])+Data(0..<32); raw.appendLE(123); raw.append(UInt8(bitPattern:-18)); raw.append(Data(repeating:0,count:3))
        let page = try NeighbourPage.decode(raw)
        XCTAssertEqual(page.total,4); XCTAssertEqual(page.entries.count,1); XCTAssertEqual(page.entries[0].key,Data(0..<32)); XCTAssertEqual(page.entries[0].heardSecondsAgo,123); XCTAssertEqual(page.entries[0].snr,-4.5)
        XCTAssertThrowsError(try NeighbourPage.decode(raw.prefix(40)))
        raw[raw.count-1] = 1; XCTAssertThrowsError(try NeighbourPage.decode(raw))
    }
    func testTelemetryBigEndianSignedTemperatureAndHalfPercentHumidity() throws {
        let report = try TelemetryReport.decode(Data([1,116,1,0x72,1,103,0xff,0xc9,2,104,125,0,0,0]))
        XCTAssertEqual(report.values.map(\.title),["Napětí","Teplota","Relativní vlhkost"])
        XCTAssertEqual(report.values.map(\.channel),[1,1,2])
        XCTAssertTrue(report.values[0].value.contains("3,7")); XCTAssertTrue(report.values[1].value.contains("-5,5")); XCTAssertTrue(report.values[2].value.contains("62,5"))
        XCTAssertNil(report.unsupportedType)
        XCTAssertThrowsError(try TelemetryReport.decode(Data([1,116,1])))
    }
    func testUnknownTelemetryStopsWithoutGuessingNextField() throws {
        let report = try TelemetryReport.decode(Data([1,116,1,0x72,2,254,1,116,1,0x72]))
        XCTAssertEqual(report.values.count,1); XCTAssertEqual(report.unsupportedType,254)
    }
    func testBinaryPushHeaderRejectsTruncationAndKeepsTag() throws {
        let raw = Data([0x8c,0,0x78,0x56,0x34,0x12,1,2,3])
        XCTAssertEqual(try MeshCodec.decode(raw),.binary(tag:0x12345678,payload:Data([1,2,3])))
        for length in 1..<6 { XCTAssertThrowsError(try MeshCodec.decode(raw.prefix(length))) }
    }
    func testClockParsingIsUTCAndRefusesMalformedOrImpossibleDates() {
        let winter = RepeaterCommand.clockDate("12:34 - 24/10/2026 UTC")
        XCTAssertNotNil(winter)
        let formatter = ISO8601DateFormatter(); XCTAssertEqual(winter.map{formatter.string(from:$0)},"2026-10-24T12:34:00Z")
        XCTAssertNil(RepeaterCommand.clockDate("12:34 - 31/2/2026 UTC"))
        XCTAssertNil(RepeaterCommand.clockDate("12:34 - 24/10/2026 CET"))
        XCTAssertTrue(CLIValidation.isErrorReply("(ERR: clock cannot go backwards)"))
    }
    func testPublicKeyPasswordAndRegionRejectInjection() throws {
        XCTAssertEqual(try RepeaterCommand.publicKey(String(repeating:"AB",count:32)),String(repeating:"ab",count:32))
        XCTAssertThrowsError(try RepeaterCommand.publicKey(String(repeating:"a",count:12)))
        XCTAssertThrowsError(try RepeaterCommand.password(String(repeating:"ž",count:8)))
        XCTAssertThrowsError(try RepeaterCommand.password("pass\nreboot"))
        XCTAssertThrowsError(try RepeaterCommand.regionName("#cz other"))
        XCTAssertThrowsError(try RepeaterCommand.regionName("#cz|#eu"))
        XCTAssertEqual(try RepeaterCommand.regionName("#cz"),"#cz")
    }
    @MainActor func testBinaryRequestMatchesEchoedTagIncludingResponseBeforeSENT() async throws {
        let t = FakeTransport(), s = MeshSession(traffic:.testing(),transport:t), key = Data(0..<32)
        t.handle = { frame in
            XCTAssertEqual(frame,Data([50])+key+Data([5,0,0]))
            t.emit(Data([0x8c,0,88,0,0,0,1])) // wrong tag
            t.emit(Data([0x8c,0,77,0,0,0,2,3])) // correct, before local receipt
            t.emit(Data([6,0,77,0,0,0,0,0,0,0]))
        }
        let reply = try await s.binary(key:key,payload:Data([5,0,0]))
        XCTAssertEqual(reply,Data([2,3])); XCTAssertEqual(t.sent.count,1)
    }
    @MainActor func testBinaryUsesSameExclusiveSessionAsCLIAndContacts() async throws {
        let t = FakeTransport(), s = MeshSession(traffic:.testing(),transport:t), key = Data(0..<32)
        let waiting = Task { try await s.binary(key:key,payload:Data([3,0,0,0])) }
        while t.sent.isEmpty { await Task.yield() }
        do { try await s.contacts(); XCTFail("Concurrent request was allowed") } catch { XCTAssertTrue(error.localizedDescription.contains("jiný")) }
        t.emit(Data([6,0,77,0,0,0,0,0,0,0])); t.emit(Data([0x8c,0,77,0,0,0,0]))
        _ = try await waiting.value
        XCTAssertEqual(t.sent.count,1)
    }
}
