import XCTest
@testable import MeshCoreKit

final class WorkspaceDataTests: XCTestCase {
    private let account = String(repeating:"11",count:32), repeater = String(repeating:"ab",count:32)
    func testShortcutsNeverSaveArgumentAndRequireCatalogCommand() throws {
        let shortcut = try ConsoleShortcut(account:account,title:"Vlastní název",command:"set name",template:true)
        XCTAssertEqual(try shortcut.filled(with:"Node B"),"set name Node B")
        XCTAssertThrowsError(try shortcut.filled(with:""))
        XCTAssertThrowsError(try shortcut.filled(with:"Node\nreboot"))
        XCTAssertThrowsError(try ConsoleShortcut(account:account,title:"Bad",command:"set name PERSONAL",template:true))
        XCTAssertThrowsError(try ConsoleShortcut(account:account,title:"Bad",command:"password SECRET",template:true))
        XCTAssertThrowsError(try ConsoleShortcut(account:account,title:"Bad",command:"get guest.password",template:false))
        let data = try JSONEncoder().encode(shortcut)
        XCTAssertFalse(String(decoding:data,as:UTF8.self).contains("Node B"))
        XCTAssertEqual(try JSONDecoder().decode(ConsoleShortcut.self,from:data),shortcut)
    }
    func testFavoritesAreReadOnlyUntilExplicitInsertionOrSend() throws {
        let favorite = try ConsoleShortcut(account:account,title:"Verze",command:"ver",template:false)
        XCTAssertEqual(try favorite.filled(with:"ignored"),"ver")
    }
    func testEvidenceDistinguishesUnsupportedFromRejectedArguments() {
        func e(_ reply: String) -> CommandEvidence { CommandEvidence(account:account,repeater:repeater,firmware:"v1.18.0",session:UUID(),command:"set name",reply:reply) }
        XCTAssertEqual(e("Unknown command").result,.unsupported)
        XCTAssertEqual(e("Not supported").result,.unsupported)
        XCTAssertEqual(e("Error: unsupported").result,.unsupported)
        XCTAssertEqual(e("Error, bad chars").result,.rejected)
        XCTAssertEqual(e("OK").result,.answered)
        XCTAssertEqual(e("> Owner text: not supported").result,.answered)
        XCTAssertFalse(CLIValidation.isErrorReply("> Owner text: not supported"))
        XCTAssertTrue(CLIValidation.isErrorReply("Error: unsupported"))
    }
    func testEvidenceIsBoundToIdentityFirmwareAndUnknownVersionSession() {
        let session = UUID()
        let known = CommandEvidence(account:account,repeater:repeater,firmware:"v1.18.0",session:session,command:"ver",reply:"version")
        XCTAssertTrue(known.matches(account:account,repeater:repeater,firmware:"v1.18.0",session:UUID()))
        XCTAssertFalse(known.matches(account:account,repeater:repeater,firmware:"v1.19.0",session:session))
        XCTAssertFalse(known.matches(account:String(repeating:"22",count:32),repeater:repeater,firmware:"v1.18.0",session:session))
        let unknown = CommandEvidence(account:account,repeater:repeater,firmware:"",session:session,command:"ver",reply:"version")
        XCTAssertFalse(unknown.matches(account:account,repeater:repeater,firmware:"",session:UUID()))
    }
    func testLegacyPendingChangesDecodeAndChecksNeverDefaultToPassed() throws {
        let raw = Data(#"{"id":"00000000-0000-0000-0000-000000000001","key":"name","date":1}"#.utf8)
        let change = try JSONDecoder().decode(UnverifiedChange.self,from:raw)
        XCTAssertNil(change.expected)
        XCTAssertEqual(VerificationAction(key:"name"),.setting("name"))
        XCTAssertEqual(VerificationAction(key:"Restart"),.status)
        XCTAssertEqual(VerificationAction(key:"Hodiny"),.clock)
        XCTAssertEqual(VerificationAction(key:"Rádio · vyžaduje restart"),.radio)
        XCTAssertEqual(VerificationAction(key:"set guest.password SECRET"),.manual)
    }
    func testHardwareCheckScopeIncludesAllVersionsAndOS() {
        func check(_ version: String = "1.18.0",os: String = "27.0.0") -> HardwareCheck { HardwareCheck(account:account,repeater:repeater,companionFirmware:"1.18.0",repeaterFirmware:version,appVersion:"0.7.0",osVersion:os,architecture:"arm64",test:.pairing,outcome:.passed) }
        XCTAssertTrue(check().sameScope(as:check()))
        XCTAssertFalse(check().sameScope(as:check("1.19.0")))
        XCTAssertFalse(check().sameScope(as:check(os:"27.1.0")))
    }
    func testReportNeverCopiesFreeTextMetadataOrRawLog() {
        XCTAssertEqual(DiagnosticReport.version("v1.18.0-PRIVATE_BRANCH"),"v1.18.0 (doplněk sestavení vynechán)")
        var input = DiagnosticReportInput()
        input.appVersion = "0.7.0 PRIVATE_NAME"; input.osVersion = "27.0.0 host@private.invalid"
        input.architecture = "SECRET_ARCH"; input.companionFirmware = "PRIVATE_NAME v1.18.0-81dbae5"
        input.repeaterFirmware = "password SECRET_FW"
        input.events = [ReportEvent(date:Date(),category:DiagnosticEvent.classify("Přijatá zpráva od PRIVATE_KEY SECRET_MESSAGE")),ReportEvent(date:Date(),category:DiagnosticEvent.classify("ARBITRARY_SECRET"))]
        input.checks = ["SECRET_CHECK"]
        let report = DiagnosticReport.render(input)
        for secret in ["PRIVATE_NAME","host@private.invalid","SECRET_ARCH","SECRET_FW","PRIVATE_KEY","SECRET_MESSAGE","ARBITRARY_SECRET","SECRET_CHECK"] { XCTAssertFalse(report.contains(secret),secret) }
        XCTAssertTrue(report.contains("v1.18.0-81dbae5")); XCTAssertTrue(report.contains("Žádný fyzický test není doložen"))
        XCTAssertFalse(DiagnosticReport.render(input,includeEvents:false).contains("Přijata LoRa zpráva"))
    }
    func testReportAllowsOnlyFiniteChecklistResults() {
        var input = DiagnosticReportInput()
        input.checks = ["\(HardwareTest.pairing.rawValue): \(HardwareOutcome.failed.rawValue)","\(HardwareTest.login.rawValue): forged"]
        let result = DiagnosticReport.render(input)
        XCTAssertTrue(result.contains("BLE připojení a párování: Selhalo"))
        XCTAssertFalse(result.contains("forged"))
    }
}
