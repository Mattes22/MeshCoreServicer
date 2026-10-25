import XCTest
@testable import MeshCoreKit

final class ConsoleCatalogTests: XCTestCase {
    func testEnumArgumentsComeOnlyFromVerifiedValuesAndRemainOptIn() {
        XCTAssertTrue(ConsoleCatalog.suggestions(for:"set repeat ").isEmpty)
        XCTAssertEqual(ConsoleCatalog.suggestions(for:"set repeat ",includeChanges:true).map(\.insertion),["set repeat on","set repeat off"])
        XCTAssertEqual(ConsoleCatalog.suggestions(for:"set loop.detect mi",includeChanges:true).map(\.insertion),["set loop.detect minimal"])
        XCTAssertEqual(ConsoleCatalog.suggestions(for:"set path.hash.mode ",includeChanges:true).map(\.insertion),["set path.hash.mode 0","set path.hash.mode 1","set path.hash.mode 2"])
    }
    func testNetworkAndOwnerArgumentsAreNeverInvented() {
        for command in ["set radio ","set name ","set lat ","set lon ","set owner.info ","set tx "] {
            XCTAssertTrue(ConsoleCatalog.suggestions(for:command,includeChanges:true).isEmpty)
        }
    }
    func testPrefixCompletesToRealRemoteCommandWithoutArguments() {
        let result = ConsoleCatalog.suggestions(for:"get ra")
        XCTAssertEqual(result.first?.insertion,"get radio")
        XCTAssertEqual(result.first?.entry?.syntax,"get radio")
        XCTAssertFalse(result.first!.entry!.changesState)
        XCTAssertEqual(ConsoleCatalog.suggestions(for:"get radio"),[])
    }
    func testCzechSearchAndPrefixRanking() {
        let result = ConsoleCatalog.suggestions(for:"radio",includeChanges:true)
        XCTAssertEqual(result.map(\.entry?.command),["get radio","set radio"])
        XCTAssertEqual(ConsoleCatalog.suggestions(for:"hodiny").first?.entry?.command,"clock")
    }
    func testWritesAreOptInAndTemplatesNeverInsertValuesOrPlaceholders() throws {
        XCTAssertTrue(ConsoleCatalog.suggestions(for:"set ").isEmpty)
        let result = ConsoleCatalog.suggestions(for:"set rad",includeChanges:true)
        XCTAssertEqual(result.first?.insertion,"set radio ")
        XCTAssertTrue(result.first!.entry!.changesState)
        XCTAssertThrowsError(try ConsoleCatalog.validate(result.first!.insertion))
        XCTAssertThrowsError(try ConsoleCatalog.validate("set radio <MHz,BW_kHz,SF,CR>"))
        XCTAssertNoThrow(try ConsoleCatalog.validate("set radio 868.0,125,7,5"))
        XCTAssertThrowsError(try ConsoleCatalog.validate("set radio 868.0,125,99,5"))
    }
    func testSensitiveAndUnsupportedLocalCommandsNeverSuggested() {
        let forbidden = ["stats-core","stats-radio","stats-packets","get acl","get prv.key","set prv.key","erase","password"]
        for value in forbidden { XCTAssertFalse(ConsoleCatalog.entries.contains(where:{$0.command == value})) }
        let history = ["get name","get guest.password","set prv.key SECRET","password SECRET","set name Node","set name Node"]
        XCTAssertTrue(ConsoleCatalog.suggestions(for:"password",history:history,includeChanges:true).isEmpty)
        XCTAssertFalse(ConsoleCatalog.suggestions(for:"get",history:history).contains(where:{$0.insertion.contains("password")}))
        XCTAssertTrue(ConsoleCatalog.suggestions(for:"set name",history:history).isEmpty)
    }
    func testHistoryIsOptionalDeduplicatedAndBounded() {
        let history = ["set name Node","set name Node","set name Another","set name Bad\nreboot"]
        let result = ConsoleCatalog.suggestions(for:"set na",history:history,includeChanges:true)
        XCTAssertEqual(result.filter(\.fromHistory).map(\.insertion),["set name Node","set name Another"])
        XCTAssertTrue(ConsoleCatalog.suggestions(for:"set na",history:history,includeHistory:false,includeChanges:true).allSatisfy{!$0.fromHistory})
        XCTAssertEqual(ConsoleCatalog.suggestions(for:"",includeChanges:true,limit:2).count,2)
        XCTAssertTrue(ConsoleCatalog.suggestions(for:"",limit:0).isEmpty)
    }
    func testKnownArgumentsValidatedAndUnknownFirmwareCommandsRemainManual() throws {
        XCTAssertThrowsError(try ConsoleCatalog.validate("set dutycycle 101"))
        XCTAssertThrowsError(try ConsoleCatalog.validate("set name " + String(repeating:"ž",count:12)))
        XCTAssertThrowsError(try ConsoleCatalog.validate("time tomorrow"))
        XCTAssertNoThrow(try ConsoleCatalog.validate("time 1800000000"))
        XCTAssertNoThrow(try ConsoleCatalog.validate("sensor get custom"))
        XCTAssertNoThrow(try ConsoleCatalog.validate("region default <null>"))
        XCTAssertThrowsError(try ConsoleCatalog.validate("ver\nreboot"))
        XCTAssertThrowsError(try ConsoleCatalog.validate("ver\0"))
        XCTAssertThrowsError(try ConsoleCatalog.validate(String(repeating:"x",count:134)))
    }
    func testLongestCommandHelpAndNoAccidentalPrefixMatch() {
        XCTAssertEqual(ConsoleCatalog.entry(for:"set flood.max.advert 4")?.command,"set flood.max.advert")
        XCTAssertNil(ConsoleCatalog.entry(for:"set nameplate Node"))
        XCTAssertNil(ConsoleCatalog.entry(for:"get radio something"))
        XCTAssertEqual(Set(ConsoleCatalog.entries.map(\.command)).count,ConsoleCatalog.entries.count)
        for key in CLIValidation.keys {
            XCTAssertNotNil(ConsoleCatalog.entry(for:"get " + key))
            XCTAssertNotNil(ConsoleCatalog.entry(for:"set " + key))
        }
    }
}
