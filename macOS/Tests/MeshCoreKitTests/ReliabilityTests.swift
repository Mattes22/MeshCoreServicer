import XCTest
@testable import MeshCoreKit

final class ReliabilityTests: XCTestCase {
    private let account = String(repeating:"1",count:64), repeater = String(repeating:"a",count:64)
    func testReconnectRequiresUserChoiceAndUsesBoundedBackoff() {
        var p = ReconnectPolicy()
        XCTAssertNil(p.nextDelay(poweredOn:true,sleeping:false))
        p.userConnect()
        XCTAssertEqual((0..<8).compactMap{_ in p.nextDelay(poweredOn:true,sleeping:false)},[1,2,4,8,16,30,30,30])
        p.connected(); XCTAssertEqual(p.nextDelay(poweredOn:true,sleeping:false),1)
        p.userDisconnect(); XCTAssertNil(p.nextDelay(poweredOn:true,sleeping:false))
    }
    func testReconnectDoesNotAdvanceWhileOffSleepingOrDisabled() {
        var p = ReconnectPolicy(); p.userConnect()
        XCTAssertNil(p.nextDelay(poweredOn:false,sleeping:false)); XCTAssertNil(p.nextDelay(poweredOn:true,sleeping:true))
        p.enabled = false; XCTAssertNil(p.nextDelay(poweredOn:true,sleeping:false)); XCTAssertEqual(p.attempt,0)
        p.enabled = true; XCTAssertEqual(p.nextDelay(poweredOn:true,sleeping:false),1)
    }
    func testSnapshotRejectsCredentialsUnknownSettingsAndConflictingDutyFields() throws {
        for values in [["password":"secret"],["guest.password":"secret"],["prv.key":"secret"],["unknown":"1"],["dutycycle":"10","af":"9"]] {
            XCTAssertThrowsError(try ConfigSnapshot(account:account,repeater:repeater,name:"Test",values:values))
        }
        XCTAssertThrowsError(try ConfigSnapshot(account:"../file",repeater:repeater,name:"Test",values:["name":"Good"]))
        let snapshot = try ConfigSnapshot(account:account,repeater:repeater,name:"Test",values:["radio":"869.432,62.5,7,5","dutycycle":"10"])
        XCTAssertEqual(snapshot.differences(current:["radio":"869.432,62.500,7,5","dutycycle":"20.0%"]),["dutycycle"])
    }
    func testSnapshotRetainsIndividualReadTimesAndRefusesUnknownReadMetadata() throws {
        let now = Date()
        let snapshot = try ConfigSnapshot(account:account,repeater:repeater,name:"Test",values:["name":"Good"],readAt:["name":now])
        let loaded = try JSONDecoder().decode(ConfigSnapshot.self,from:JSONEncoder().encode(snapshot)); XCTAssertEqual(loaded,snapshot)
        XCTAssertThrowsError(try ConfigSnapshot(account:account,repeater:repeater,name:"Test",values:["name":"Good"],readAt:["password":now]))
    }
    func testChatArchiveCompatibilityWithoutCaptureField() throws {
        let record = ChatRecord(conversationID:"channel:0:test",title:"Test",channelIndex:0,outgoing:false,sender:"Peer",text:"Text",timestamp:1,delivery:.received)
        let data = try JSONEncoder().encode(record)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any]); object.removeValue(forKey:"captures")
        let old = try JSONDecoder().decode(ChatRecord.self,from:JSONSerialization.data(withJSONObject:object)); XCTAssertNil(old.captures); XCTAssertEqual(old.text,"Text")
    }
}
