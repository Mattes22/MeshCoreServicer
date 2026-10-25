import XCTest
import MeshCoreKit
@testable import MeshCoreServicer

@MainActor final class ToolsTransport: MeshTransport {
    var onFrame: ((Data)->Void)?
    var onDisconnect: (()->Void)?
    var statusReply: Data?
    var failStatus = false
    var commands: [String] = []
    var frames: [Data] = []
    var values = ["flood.advert.interval":"12","advert.interval":"120","dutycycle":"10.0%","af":"9","path.hash.mode":"0","owner.info":"Jan - jan@example.net"]
    var reply: ((String)->String?)?
    var binaryReply: ((Data)->Data)?
    private var queued: [String] = []
    private var sequence: UInt32 = 1
    func write(_ frame: Data) async throws {
        frames.append(frame)
        if frame[0] == 10 {
            guard !queued.isEmpty else { onFrame?(Data([10])); return }
            var d = Data([7])+Data(repeating:0xab,count:6)+Data([255,1]); d.appendLE(sequence); sequence += 1; d.append(Data(queued.removeFirst().utf8)); onFrame?(d)
        } else if frame[0] == 2 {
            let command = String(decoding:frame.dropFirst(13),as:UTF8.self); commands.append(command)
            onFrame?(Data([6,0,0,0,0,0,0,0,0,0]))
            if let custom = reply?(command) { queued.append(custom); return }
            if command == "ver" { queued.append("RAK4631 Repeater v1.18.0-81dbae5") }
            else if command.hasPrefix("get ") { queued.append(values[String(command.dropFirst(4))].map{"> " + $0} ?? "Unknown command") }
            else if command.hasPrefix("set ") {
                let parts = command.split(separator:" ",maxSplits:2).map(String.init)
                if parts.count == 3 { values[parts[1]] = parts[2]; queued.append("OK") } else { queued.append("Error") }
            } else { queued.append("OK") }
        } else if frame[0] == 27 {
            if failStatus { throw MeshError.disconnected }
            guard let statusReply else { XCTFail("Unexpected status request"); return }
            onFrame?(Data([6,0,77,0,0,0,0,0,0,0])); onFrame?(Data([0x87,0])+frame.dropFirst().prefix(6)+statusReply)
        } else if frame[0] == 50, let binaryReply {
            onFrame?(Data([6,0,77,0,0,0,0,0,0,0]))
            onFrame?(Data([0x8c,0,77,0,0,0])+binaryReply(Data(frame.dropFirst(33))))
        } else { XCTFail("Unexpected opcode \(frame[0])") }
    }
}
final class RepeaterToolsModelTests: XCTestCase {
    @MainActor func testUniversalSetupDefaultPreservesDeviceAndNeverTransmitsOnProfileSelection() async throws {
        let (m,t) = fixture()
        // The shared fixture explicitly enables the Czech profile; verify production defaults separately.
        XCTAssertFalse(RepeaterToolsState().useCzechProfile)
        XCTAssertFalse(RepeaterToolsState().communitySyncClock)
        m.chooseSetupProfile(czech:false); m.tools.communitySyncClock = false
        m.loadCommunitySetup(); try await finished(m)
        XCTAssertTrue(m.tools.communitySelected.isEmpty)
        let before = t.commands
        m.applyCommunitySetup(); XCTAssertNil(m.confirmation); XCTAssertEqual(t.commands,before)
        m.chooseSetupProfile(czech:true)
        XCTAssertEqual(m.tools.communitySelected,["flood.advert.interval","advert.interval","path.hash.mode"])
        XCTAssertEqual(t.commands,before)
        m.chooseSetupProfile(czech:false)
        XCTAssertTrue(m.tools.communitySelected.isEmpty); XCTAssertEqual(t.commands,before)
    }
    @MainActor func testConsoleRejectsIncompleteKnownCommandBeforeTransportOrHistory() {
        let (m,t) = fixture()
        for command in ["set name ","set dutycycle 101","set radio <MHz,BW_kHz,SF,CR>"] {
            m.command = command; m.sendCLI()
            XCTAssertNotNil(m.error); XCTAssertTrue(t.frames.isEmpty); XCTAssertTrue(m.console.isEmpty); XCTAssertTrue(m.history.isEmpty)
        }
    }
    @MainActor private func fixture() -> (AppModel,ToolsTransport) {
        let t = ToolsTransport(), model = AppModel(traffic:.testing(),ble:BluetoothTransport(startImmediately:false),transport:t)
        let c = Contact(key:Data(repeating:0xab,count:32),kind:2,name:"Test",stored:true)
        model.contacts = [c]; model.selectedID = c.id; model.initialized = true; model.adminID = c.id
        model.chooseSetupProfile(czech:true); model.tools.communitySyncClock = true
        return (model,t)
    }
    @MainActor private func finished(_ model: AppModel) async throws {
        for _ in 0..<2000 { if !model.busy { return }; try await Task.sleep(nanoseconds:1_000_000) }
        XCTFail("Operation did not finish")
    }
    @MainActor private func confirm(_ model: AppModel) { let action = model.confirmation?.action; model.confirmation = nil; action?() }
    @MainActor func testOpeningModelDoesNotSendAndChangingTargetClearsSetup() {
        let (m,t) = fixture(); XCTAssertTrue(t.frames.isEmpty)
        m.tools.communityLoaded = true; m.tools.communityOwner = "Private owner"; m.selectedID = "other"
        XCTAssertFalse(m.tools.communityLoaded); XCTAssertTrue(m.tools.communityOwner.isEmpty); XCTAssertTrue(t.frames.isEmpty)
    }
    @MainActor func testCommunityReadOnlySelectsSupportedDifferentValues() async throws {
        let (m,t) = fixture(); m.loadCommunitySetup(); try await finished(m)
        XCTAssertTrue(m.tools.communityLoaded); XCTAssertEqual(m.tools.communityDutyKey,"dutycycle")
        XCTAssertEqual(m.tools.communitySelected,["flood.advert.interval","advert.interval","path.hash.mode"])
        XCTAssertFalse(t.commands.contains(where:{$0.hasPrefix("set ") || $0.hasPrefix("time ")}))
        XCTAssertFalse(t.commands.contains("get af"))
    }
    @MainActor func testLegacyDutyFallbackIsReadThenOnlyOneWrite() async throws {
        let (m,t) = fixture(); t.values["dutycycle"] = nil; t.values["af"] = "1"
        m.loadCommunitySetup(); try await finished(m)
        XCTAssertEqual(m.tools.communityDutyKey,"af"); XCTAssertTrue(t.commands.contains("get af"))
        m.tools.communitySelected = ["af"]; m.tools.communitySyncClock = false
        let before = t.commands; m.applyCommunitySetup(); XCTAssertEqual(t.commands,before)
        confirm(m); try await finished(m)
        XCTAssertEqual(Array(t.commands.dropFirst(before.count)),["set af 9","get af"])
        XCTAssertEqual(m.config["af"],"9"); XCTAssertFalse(t.commands.contains("set dutycycle 10"))
    }
    @MainActor func testSetupIsReviewedAndEveryMutationReadBackWithoutRadioOrRestart() async throws {
        let (m,t) = fixture(); m.loadCommunitySetup(); try await finished(m); m.tools.communitySyncClock = false
        t.commands = []; m.applyCommunitySetup()
        XCTAssertTrue(t.commands.isEmpty); XCTAssertNotNil(m.confirmation)
        XCTAssertTrue(m.confirmation!.message.contains("12 → 25"))
        confirm(m); try await finished(m)
        XCTAssertEqual(t.commands,["set flood.advert.interval 25","get flood.advert.interval","set advert.interval 0","get advert.interval","set path.hash.mode 1","get path.hash.mode"])
        XCTAssertEqual(m.completedSteps,3); XCTAssertTrue(m.tools.communitySelected.isEmpty)
    }
    @MainActor func testSetupStopsAtFirstFailureAndPreservesRemainingSteps() async throws {
        let (m,t) = fixture(); m.loadCommunitySetup(); try await finished(m); m.tools.communitySyncClock = false
        t.reply = { $0 == "set advert.interval 0" ? "Error, rejected" : nil }
        t.commands = []; m.applyCommunitySetup(); confirm(m); try await finished(m)
        XCTAssertEqual(t.commands,["set flood.advert.interval 25","get flood.advert.interval","set advert.interval 0"])
        XCTAssertEqual(m.completedSteps,1); XCTAssertTrue(m.tools.communitySelected.contains("path.hash.mode")); XCTAssertNotNil(m.error)
    }
    @MainActor func testUnsupportedStepAndInvalidOwnerCannotBeSent() async throws {
        let (m,t) = fixture(); t.values["path.hash.mode"] = nil
        m.loadCommunitySetup(); try await finished(m)
        XCTAssertFalse(m.tools.communitySelected.contains("path.hash.mode"))
        m.tools.communityOwner = String(repeating:"ž",count:60); m.tools.communitySelected = ["owner.info"]
        t.commands = []; m.applyCommunitySetup()
        XCTAssertNotNil(m.error); XCTAssertNil(m.confirmation); XCTAssertTrue(t.commands.isEmpty)
    }
    @MainActor func testDutyPercentReadbackAndAlternateInvalidation() async throws {
        let (m,t) = fixture(); m.config = ["dutycycle":"20.0%","af":"4"]; m.edits = ["dutycycle":"10%","af":"4"]
        t.reply = { $0 == "get dutycycle" ? "> 10.0%" : nil }
        m.save("dutycycle"); try await finished(m)
        XCTAssertEqual(t.commands,["set dutycycle 10","get dutycycle"])
        XCTAssertTrue(m.dirtyKeys.isEmpty); XCTAssertNil(m.config["af"]); XCTAssertNil(m.error)
    }
    @MainActor func testCannotBatchConflictingDutyAndAirtimeWrites() {
        let (m,t) = fixture(); m.config = ["dutycycle":"20","af":"4"]; m.edits = ["dutycycle":"10","af":"9"]
        m.saveChanges(); XCTAssertNotNil(m.error); XCTAssertTrue(t.commands.isEmpty)
    }
    @MainActor func testClockUsesExplicitMacEpochAndRefusesBackwardsReply() async throws {
        let (m,t) = fixture()
        t.reply = { command in
            if command.hasPrefix("time ") { return "(ERR: clock cannot go backwards)" }; return nil
        }
        m.syncRepeaterClock(); XCTAssertTrue(t.commands.isEmpty); confirm(m); try await finished(m)
        XCTAssertEqual(t.commands.count,1); XCTAssertTrue(t.commands[0].hasPrefix("time ")); XCTAssertFalse(t.commands.contains("clock sync")); XCTAssertNotNil(m.error)
        XCTAssertTrue(m.tools.clockResult?.contains("nebyla plně ověřena") == true)
    }
    @MainActor func testClockConfirmationThenReadbackMustMatchCurrentUTC() async throws {
        let (m,t) = fixture()
        let f = DateFormatter(); f.locale = Locale(identifier:"en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT:0); f.dateFormat = "HH:mm - d/M/yyyy 'UTC'"
        t.reply = { command in if command.hasPrefix("time ") { return "OK - clock set" }; if command == "clock" { return f.string(from:Date()) }; return nil }
        m.syncRepeaterClock(); confirm(m); try await finished(m)
        XCTAssertEqual(t.commands.count,2); XCTAssertEqual(t.commands.last,"clock"); XCTAssertNotNil(m.tools.clockRead); XCTAssertNil(m.error)
    }
    @MainActor func testGuestPasswordDoesNotAppearInConsoleHistoryOrDiagnostics() async throws {
        let (m,t) = fixture(); m.changeRemotePassword("Test-Secret",guest:true,saveToKeychain:false)
        XCTAssertTrue(t.commands.isEmpty); XCTAssertFalse(m.confirmation!.message.contains("Test-Secret"))
        confirm(m); try await finished(m)
        XCTAssertEqual(t.commands,["set guest.password Test-Secret"])
        XCTAssertTrue(m.console.isEmpty); XCTAssertTrue(m.history.isEmpty)
        XCTAssertFalse(m.logs.contains(where:{$0.text.contains("Test-Secret")})); XCTAssertEqual(m.clean("Test-Secret"),"[skryto]")
    }
    @MainActor func testRegionPrefixMismatchDoesNotMutateOrSave() async throws {
        let (m,t) = fixture(); t.reply = { $0 == "region get #cz" ? " #cz.other F" : nil }
        m.changeRegion(operation:"denyf",name:"#cz",parent:""); confirm(m); try await finished(m)
        XCTAssertEqual(t.commands,["region get #cz"]); XCTAssertNotNil(m.error)
    }
    @MainActor func testRegionMutationSavesThenReloadsInOrder() async throws {
        let (m,t) = fixture(); t.reply = { $0 == "region get #cz" ? " #cz F" : nil }
        m.changeRegion(operation:"denyf",name:"#cz",parent:""); confirm(m); try await finished(m)
        XCTAssertEqual(t.commands,["region get #cz","region denyf #cz","region save","region","region home","region default"])
        XCTAssertNil(m.error)
    }
    @MainActor func testNeighboursFollowAllPagesAndLabelRemoteSNR() async throws {
        let (m,t) = fixture()
        t.binaryReply = { payload in
            XCTAssertEqual(payload[0],6); XCTAssertEqual(payload[6],32)
            let offset = Int(payload[3]) + Int(payload[4])*256
            var raw = Data([4,0,UInt8(offset == 0 ? 3 : 1),0])
            for i in offset..<min(offset+3,4) {
                raw.append(Data(repeating:UInt8(i+1),count:32)); raw.appendLE(UInt32(i*60)); raw.append(UInt8(bitPattern:-12))
            }
            return raw
        }
        m.readNeighbours(); try await finished(m)
        XCTAssertEqual(t.frames.map{$0[0]},[50,50]); XCTAssertEqual(m.tools.neighbours.count,4)
        XCTAssertEqual(m.tools.neighbourTotal,4); XCTAssertNotNil(m.tools.neighbourDate)
        XCTAssertEqual(m.tools.neighbours.last?.heardSecondsAgo,180); XCTAssertEqual(m.tools.neighbours[0].snr,-3)
    }
    @MainActor func testACLReadAndTelemetryUseTaggedBinaryOperations() async throws {
        let (m,t) = fixture()
        t.binaryReply = { payload in
            if payload[0] == 5 { XCTAssertEqual(payload,Data([5,0,0])); return Data(repeating:0xee,count:6)+Data([3])+Data(repeating:0,count:5) }
            XCTAssertEqual(payload,Data([3,0,0,0])); return Data([1,116,1,0x72,0,0,0,0])
        }
        m.readAccess(); try await finished(m)
        XCTAssertEqual(m.tools.access.count,1); XCTAssertEqual(m.tools.access[0].permissions,3)
        m.readTelemetry(); try await finished(m)
        XCTAssertEqual(m.tools.telemetry?.values.count,1); XCTAssertNotNil(m.tools.telemetryDate)
        XCTAssertTrue(t.commands.isEmpty); XCTAssertEqual(t.frames.map{$0[0]},[50,50])
    }
    @MainActor func testCannotRemoveOwnCompanionAccess() throws {
        let (m,t) = fixture()
        var raw = Data([5,0,0,0])+Data(repeating:0xee,count:32)+Data(repeating:0,count:12)
        raw.appendLE(869432); raw.appendLE(62500); raw.append(contentsOf:[7,5]); raw.append(Data("Me".utf8))
        m.event(try MeshCodec.decode(raw))
        m.changeAccess(publicKey:String(repeating:"ee",count:32),permissions:0)
        XCTAssertNil(m.confirmation); XCTAssertNotNil(m.error); XCTAssertTrue(t.frames.isEmpty)
    }
    @MainActor func testConfirmationForOldTargetCannotWriteToIt() async throws {
        let (m,t) = fixture(); m.loadCommunitySetup(); try await finished(m)
        m.applyCommunitySetup(); XCTAssertNotNil(m.confirmation)
        let action = m.confirmation!.action; t.commands = []
        m.selectedID = "other"; action()
        XCTAssertTrue(t.commands.isEmpty); XCTAssertFalse(m.busy)
    }
    @MainActor func testACLRoleChangePreservesLoadedUpperPermissionBits() async throws {
        let (m,t) = fixture(), prefix = Data(repeating:0xee,count:6)
        m.tools.access = try AccessEntry.decode(prefix+Data([0x83])); m.tools.accessDate = Date()
        t.binaryReply = { _ in prefix+Data([0x81]) }
        m.changeAccess(publicKey:String(repeating:"ee",count:32),permissions:1)
        XCTAssertTrue(t.commands.isEmpty); confirm(m); try await finished(m)
        XCTAssertEqual(t.commands,["setperm \(String(repeating:"ee",count:32)) 129"])
        XCTAssertEqual(m.tools.access.first?.permissions,0x81); XCTAssertNil(m.error)
    }
}
