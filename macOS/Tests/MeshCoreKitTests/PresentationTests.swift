import XCTest
@testable import MeshCoreKit

final class PresentationTests: XCTestCase {
    func testSearchCombinesNameKeyAndTypeWithoutLosingScope() {
        let repeater = Contact(key:Data(repeating:0xab,count:32),kind:2,name:"Žižkov Solar",stored:true)
        let companion = Contact(key:Data(repeating:0xcd,count:32),kind:1,name:"Companion A",stored:true)
        let newNode = Contact(key:Data(repeating:0xef,count:32),kind:2,name:"Lesní uzel")
        let all = [repeater,companion,newNode]
        XCTAssertEqual(ContactQuery.filter(all,search:"zizkov abab",scope:.repeaters),[repeater])
        XCTAssertTrue(ContactQuery.filter(all,search:"Companion",scope:.repeaters).isEmpty)
        XCTAssertEqual(ContactQuery.filter(all,search:"",scope:.unstored),[newNode])
        XCTAssertEqual(ContactQuery.filter(all,search:"companion",scope:.all),[companion])
    }
    func testEncodedPathDoesNotMistakeHashSizeForHopCount() {
        var c = Contact(key:Data(repeating:0,count:32),kind:2,name:"Test")
        XCTAssertEqual(MeshPresentation.route(c),"Flood · cesta neznámá")
        c.outPathLength = 0; XCTAssertEqual(MeshPresentation.route(c),"Přímá cesta")
        c.outPathLength = 0x42; XCTAssertEqual(MeshPresentation.route(c),"2 hopy · 2 B/hash")
        c.outPathLength = 0xc1; XCTAssertEqual(MeshPresentation.route(c),"Neplatná cesta")
        c.outPathLength = 0x9f; XCTAssertEqual(MeshPresentation.route(c),"Neplatná cesta")
    }
    func testReadbackComparisonAcceptsFormattingButRejectsWrongValues() {
        XCTAssertTrue(MeshPresentation.sameValue(key:"radio","869.432,62.500,7,5","869.432000,62.5,7,5"))
        XCTAssertFalse(MeshPresentation.sameValue(key:"radio","869.432,62.5,7,5","869.525,62.5,7,5"))
        XCTAssertTrue(MeshPresentation.sameValue(key:"lat","50.100000","50.1"))
        XCTAssertFalse(MeshPresentation.sameValue(key:"lat","nan","nan"))
        XCTAssertFalse(MeshPresentation.sameValue(key:"name","Companion","companion"))
    }
    func testRadioDraftPreservesIndividualFields() throws {
        var draft = RadioDraft("869.432,62.500,7,5")
        XCTAssertEqual(draft.bandwidth,"62.5")
        draft.spreadingFactor = "8"
        XCTAssertEqual(draft.rawValue,"869.432,62.5,8,5")
        XCTAssertNoThrow(try CLIValidation.validate(key:"radio",value:draft.rawValue))
        XCTAssertEqual(RadioDraft("").rawValue,",,,")
    }
    func testHistoryRestoresDraftAndStopsAtBoundaries() {
        var navigator = CommandHistoryNavigator()
        let history = ["get radio","ver"]
        XCTAssertEqual(navigator.previous(current:"get na",history:history),"get radio")
        XCTAssertEqual(navigator.previous(current:"get radio",history:history),"ver")
        XCTAssertEqual(navigator.previous(current:"ver",history:history),"ver")
        XCTAssertEqual(navigator.next(current:"ver",history:history),"get radio")
        XCTAssertEqual(navigator.next(current:"get radio",history:history),"get na")
        XCTAssertEqual(navigator.next(current:"get na",history:history),"get na")
        navigator.reset()
        XCTAssertEqual(navigator.previous(current:"draft",history:[]),"draft")
    }
    func testHumanDurationsPreserveSmallValues() {
        XCTAssertEqual(MeshPresentation.duration(0),"0 s")
        XCTAssertEqual(MeshPresentation.duration(65),"1 min 5 s")
        XCTAssertEqual(MeshPresentation.duration(3720),"1 h 2 min")
        XCTAssertEqual(MeshPresentation.duration(90000),"1 d 1 h 0 min")
    }
}
