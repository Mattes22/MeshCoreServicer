import XCTest
import MeshCoreKit
@testable import MeshCoreServicer

final class WorkspaceModelTests: XCTestCase {
    private let account = String(repeating:"11",count:32)
    @MainActor func testOptionsEditedBeforeFirstConnectionBecomeNewProfileDefaults() throws {
        let m = AppModel(traffic:.testing(),ble:BluetoothTransport(startImmediately:false))
        m.preferences.consoleSuggestions = false; m.monitorIntervalMinutes = 40
        try identity(m,byte:0x11)
        XCTAssertFalse(m.preferences.consoleSuggestions); XCTAssertEqual(m.monitorIntervalMinutes,40)
        XCTAssertEqual(m.library.profile?.options.diagnosticMinutes,40)
    }
    @MainActor private func identity(_ m: AppModel,byte: UInt8) throws {
        var d = Data([5,0,0,0])+Data(repeating:byte,count:32)+Data(repeating:0,count:12)
        d.appendLE(868000); d.appendLE(125000); d.append(contentsOf:[7,5]); d.append(Data("Companion test".utf8)); m.event(try MeshCodec.decode(d))
    }
    @MainActor private func fixture() async throws -> (AppModel,ToolsTransport,Contact) {
        let t = ToolsTransport(), m = AppModel(traffic:.testing(),ble:BluetoothTransport(startImmediately:false),transport:t)
        try identity(m,byte:0x11)
        let c = Contact(key:Data(repeating:0xab,count:32),kind:2,name:"Test node",stored:true)
        m.contacts = [c]; m.selectedID = c.id; m.initialized = true; m.adminID = c.id
        await m.operations.activate(account:account); m.operations.select(c.id)
        t.values["name"] = "Wanted"; t.values["radio"] = "868,125,7,5"
        return (m,t,c)
    }
    @MainActor private func finish(_ m: AppModel) async throws {
        for _ in 0..<2000 { if !m.busy { return }; try await Task.sleep(nanoseconds:1_000_000) }; XCTFail("Operation did not finish")
    }
    @MainActor func testProfilesRestoreOwnPreferencesAndClearConsoleAcrossIdentities() async throws {
        let (m,t,_) = try await fixture()
        m.preferences.consoleSuggestions = false; m.monitorIntervalMinutes = 45; m.preferences.showMessageText = true
        m.command = "private draft"; m.history = ["get name"]; m.console = [ConsoleLine(target:"Test",targetID:"old",command:"get name",response:"PRIVATE")]
        m.log("Previous profile event"); m.knownSecrets.insert("OLD_SECRET")
        try identity(m,byte:0x22)
        XCTAssertTrue(m.preferences.consoleSuggestions); XCTAssertEqual(m.monitorIntervalMinutes,30)
        XCTAssertTrue(m.preferences.showMessageText,"Privacy preference stays global")
        XCTAssertTrue(m.history.isEmpty); XCTAssertTrue(m.command.isEmpty); XCTAssertTrue(m.console.isEmpty)
        XCTAssertTrue(m.logs.isEmpty); XCTAssertTrue(m.knownSecrets.isEmpty)
        XCTAssertNil(m.selectedID); XCTAssertNil(m.adminID)
        try identity(m,byte:0x11)
        XCTAssertFalse(m.preferences.consoleSuggestions); XCTAssertEqual(m.monitorIntervalMinutes,45)
        XCTAssertTrue(t.frames.isEmpty)
    }
    @MainActor func testWrongIdentityForRequestedProfileIsRejectedWithoutRadio() async throws {
        let (m,t,_) = try await fixture()
        m.requestedProfileID = account
        try identity(m,byte:0x22)
        XCTAssertEqual(m.selfInfo?.key.hex,account)
        XCTAssertNotNil(m.error); XCTAssertEqual(m.library.document.profiles.count,1)
        XCTAssertTrue(t.frames.isEmpty)
    }
    @MainActor func testLibraryRoundTripStoresNoTemplateArgumentAndPreservesCorruptData() throws {
        let suite = "WorkspaceTests." + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let library = WorkspaceLibrary(defaults:defaults)
        try library.activate(account:account,name:"Test",bluetoothID:UUID(),defaults:DevicePreferences())
        try library.rename(account,alias:"Místní alias")
        try library.saveShortcut(title:"Přejmenovat",command:"set name",template:true)
        XCTAssertEqual(try library.shortcuts[0].filled(with:"PERSONAL_ARGUMENT"),"set name PERSONAL_ARGUMENT")
        let data = try XCTUnwrap(defaults.data(forKey:"workspaceLibrary"))
        XCTAssertFalse(String(decoding:data,as:UTF8.self).contains("PERSONAL_ARGUMENT"))
        let restored = WorkspaceLibrary(defaults:defaults)
        try restored.activate(account:account,name:"Test",bluetoothID:nil,defaults:DevicePreferences())
        XCTAssertEqual(restored.profile?.alias,"Místní alias"); XCTAssertEqual(restored.shortcuts.count,1)
        let corrupt = Data("not JSON".utf8); defaults.set(corrupt,forKey:"workspaceLibrary")
        let broken = WorkspaceLibrary(defaults:defaults)
        try broken.activate(account:account,name:"Test",bluetoothID:nil,defaults:DevicePreferences())
        XCTAssertNotNil(broken.storageError); XCTAssertEqual(defaults.data(forKey:"workspaceLibrary"),corrupt)
    }
    @MainActor func testShortcutAndEvidenceAreIsolatedBetweenProfiles() throws {
        let l = WorkspaceLibrary(), session = UUID(), repeater = String(repeating:"ab",count:32)
        try l.activate(account:account,name:"One",bluetoothID:nil,defaults:DevicePreferences())
        try l.saveShortcut(title:"Verze",command:"ver",template:false)
        l.record(CommandEvidence(account:account,repeater:repeater,firmware:"v1.18.0",session:session,command:"ver",reply:"Version"))
        try l.activate(account:String(repeating:"22",count:32),name:"Two",bluetoothID:nil,defaults:DevicePreferences())
        XCTAssertTrue(l.shortcuts.isEmpty); XCTAssertNil(l.support(command:"ver",repeater:repeater,firmware:"v1.18.0",session:session))
        try l.activate(account:account,name:"One",bluetoothID:nil,defaults:DevicePreferences())
        XCTAssertEqual(l.shortcuts.count,1); XCTAssertNotNil(l.support(command:"ver",repeater:repeater,firmware:"v1.18.0",session:UUID()))
    }
    @MainActor func testAllCLIReadersFeedEvidenceAndFirmwareChangeInvalidatesIt() async throws {
        let (m,t,_) = try await fixture()
        m.sendCLI("ver"); try await finish(m)
        XCTAssertEqual(m.evidence(for:"ver")?.result,.answered)
        m.readConfig(keys:["name","tx"]); try await finish(m)
        XCTAssertEqual(m.evidence(for:"get name")?.result,.answered)
        XCTAssertEqual(m.evidence(for:"get tx")?.result,.unsupported)
        XCTAssertEqual(t.commands,["ver","get name","get tx"])
        m.tools.firmware = "v1.19.0-abcdef0"
        XCTAssertNil(m.evidence(for:"get name"))
    }
    @MainActor func testEvidenceDoesNotMixDifferentPrereleaseBuilds() async throws {
        let (m,_,_) = try await fixture()
        m.tools.firmware = "v1.18.0-beta1"
        m.sendCLI("get name"); try await finish(m)
        XCTAssertNotNil(m.evidence(for:"get name"))
        m.tools.firmware = "v1.18.0-beta2"
        XCTAssertNil(m.evidence(for:"get name"))
    }
    @MainActor func testNoReplyCommandIsNotEvidenceOfRemoteSupport() async throws {
        let (m,_,_) = try await fixture()
        m.sendCLI("reboot",confirmed:true); try await finish(m)
        XCTAssertNil(m.evidence(for:"reboot"))
        XCTAssertTrue(m.operations.current.unverified.contains(where:{$0.key == "Restart"}))
    }
    @MainActor func testVerificationOnlyReadsAndResolvesMatchingDesiredValue() async throws {
        let (m,t,c) = try await fixture()
        m.operations.beginChange("name",repeater:c.id,expected:"Wanted")
        m.fieldErrors["name"] = "Old failure"
        m.verifyChange(try XCTUnwrap(m.operations.current.unverified.first)); try await finish(m)
        XCTAssertEqual(t.commands,["get name"]); XCTAssertTrue(m.operations.current.unverified.isEmpty)
        XCTAssertEqual(m.config["name"],"Wanted")
        XCTAssertNil(m.fieldErrors["name"]); XCTAssertNotNil(m.verified[c.id])
    }
    @MainActor func testDifferentOrLegacyValueStaysUnverified() async throws {
        let (m,t,c) = try await fixture()
        for expected in ["Other",nil] as [String?] {
            m.operations.beginChange("name",repeater:c.id,expected:expected)
            m.verifyChange(try XCTUnwrap(m.operations.current.unverified.first)); try await finish(m)
            XCTAssertEqual(m.operations.current.unverified.count,1)
        }
        XCTAssertEqual(t.commands,["get name","get name"])
    }
    @MainActor func testRadioReadDoesNotConfirmAppliedRadioOrRestart() async throws {
        let (m,t,c) = try await fixture()
        m.operations.beginChange("Rádio · vyžaduje restart",repeater:c.id)
        m.verifyChange(try XCTUnwrap(m.operations.current.unverified.first)); try await finish(m)
        XCTAssertEqual(t.commands,["get radio"]); XCTAssertEqual(m.operations.current.unverified.count,1)
        XCTAssertTrue(m.notice?.contains("nepotvrzuje") == true)
    }
    @MainActor func testPoisonedSessionBlocksVerificationUntilReconnect() async throws {
        let (m,t,c) = try await fixture()
        m.operations.beginChange("name",repeater:c.id,expected:"Wanted")
        t.failStatus = true; m.ping(); try await finish(m)
        XCTAssertTrue(m.session.requiresReconnect)
        let frames = t.frames
        m.verifyChange(try XCTUnwrap(m.operations.current.unverified.first))
        XCTAssertEqual(t.frames,frames); XCTAssertEqual(m.operations.current.unverified.count,1)
        m.session.reset(); XCTAssertFalse(m.session.requiresReconnect)
    }
    @MainActor func testReportUsesCategoriesInsteadOfLogTextAndCLI() async throws {
        let (m,_,_) = try await fixture()
        m.log("Přijatá zpráva od PRIVATE_KEY SECRET_MESSAGE")
        m.log("UNKNOWN SECRET_EVENT")
        m.console = [ConsoleLine(target:"PRIVATE_NAME",targetID:"PRIVATE_KEY",command:"password SECRET_PASSWORD",response:"SECRET_REPLY")]
        let report = DiagnosticReport.render(m.reportInput())
        for value in ["PRIVATE_KEY","SECRET_MESSAGE","SECRET_EVENT","PRIVATE_NAME","SECRET_PASSWORD","SECRET_REPLY"] { XCTAssertFalse(report.contains(value)) }
    }
    @MainActor func testHardwareChecksStartEmptyAndCanRecordScopedOfflineFailure() throws {
        let library = WorkspaceLibrary()
        try library.activate(account:account,name:"Test",bluetoothID:nil,defaults:DevicePreferences())
        XCTAssertTrue(library.document.checks.isEmpty)
        let check = HardwareCheck(account:account,repeater:String(repeating:"ab",count:32),companionFirmware:"1.18.0",repeaterFirmware:"1.18.0",appVersion:"0.7.0",osVersion:"27.0.0",architecture:"arm64",test:.reconnect,outcome:.failed)
        library.deactivate(); library.recordCheck(check)
        XCTAssertEqual(library.document.checks,[check])
    }
}
