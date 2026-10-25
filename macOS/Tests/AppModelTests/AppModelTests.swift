import XCTest
import MeshCoreKit
@testable import MeshCoreServicer

@MainActor private final class ScriptedTransport: MeshTransport {
    var onFrame: ((Data)->Void)?
    var onDisconnect: (()->Void)?
    var commands: [String] = []
    var answer: (String)->String? = { _ in "OK" }
    private var messages: [String] = []
    private var timestamp: UInt32 = 1
    func write(_ frame: Data) async throws {
        if frame.first == 10 {
            guard !messages.isEmpty else { onFrame?(Data([10])); return }
            let reply = messages.removeFirst()
            var d = Data([7])+Data(repeating:0xab,count:6)+Data([255,1]); d.appendLE(timestamp); timestamp += 1; d.append(Data(reply.utf8)); onFrame?(d)
        } else if frame.first == 2 {
            let command = String(decoding:frame.dropFirst(13),as:UTF8.self)
            commands.append(command)
            onFrame?(Data([6,0,0,0,0,0,0,0,0,0]))
            if let reply = answer(command) { messages.append(reply) }
        } else { XCTFail("Unexpected opcode") }
    }
}
final class AppModelTests: XCTestCase {
    @MainActor private func fixture() -> (AppModel,ScriptedTransport) {
        let transport = ScriptedTransport()
        let model = AppModel(ble:BluetoothTransport(startImmediately:false),transport:transport)
        let contact = Contact(key:Data(repeating:0xab,count:32),kind:2,name:"Test",stored:true)
        model.contacts = [contact]; model.selectedID = contact.id; model.initialized = true; model.adminID = contact.id
        return (model,transport)
    }
    @MainActor private func finished(_ model: AppModel) async throws {
        let deadline = Date().addingTimeInterval(2)
        while model.busy && Date() < deadline { try await Task.sleep(nanoseconds:1_000_000) }
        XCTAssertFalse(model.busy,"Operation did not finish")
    }
    @MainActor func testSingleSaveRequiresMatchingReadback() async throws {
        let (model,t) = fixture()
        model.config = ["name":"Before"]; model.edits = ["name":"After"]
        t.answer = { $0 == "get name" ? "> After" : "OK" }
        model.save("name"); try await finished(model)
        XCTAssertEqual(t.commands,["set name After","get name"])
        XCTAssertEqual(model.config["name"],"After"); XCTAssertTrue(model.dirtyKeys.isEmpty)
        XCTAssertEqual(model.fieldStates["name"],.confirmed)
    }
    @MainActor func testMismatchedReadbackPreservesDraft() async throws {
        let (model,t) = fixture()
        model.config = ["tx":"17"]; model.edits = ["tx":"20"]
        t.answer = { $0 == "get tx" ? "> 19" : "OK" }
        model.save("tx"); try await finished(model)
        XCTAssertEqual(model.config["tx"],"19"); XCTAssertEqual(model.edits["tx"],"20")
        XCTAssertEqual(model.fieldStates["tx"],.different); XCTAssertNotNil(model.error)
    }
    @MainActor func testBatchIsReviewedAndStopsAfterFailure() async throws {
        let (model,t) = fixture()
        model.config = ["name":"Before","tx":"17","repeat":"on"]
        model.edits = ["name":"After","tx":"18","repeat":"off"]
        t.answer = { c in
            if c == "get name" { return "> After" }
            if c == "set tx 18" { return "Error, unsupported" }
            return "OK"
        }
        model.saveChanges()
        XCTAssertTrue(t.commands.isEmpty); XCTAssertNotNil(model.confirmation)
        let action = model.confirmation?.action; model.confirmation = nil; action?()
        try await finished(model)
        XCTAssertEqual(t.commands,["set name After","get name","set tx 18"])
        XCTAssertEqual(model.completedSteps,1); XCTAssertEqual(model.totalSteps,3)
        XCTAssertEqual(model.config["name"],"After"); XCTAssertEqual(model.edits["tx"],"18"); XCTAssertEqual(model.edits["repeat"],"off")
    }
    @MainActor func testRadioSaveWarnsAndRecordsRestartOnlyAfterResponse() async throws {
        let (model,t) = fixture()
        model.config = ["radio":"869.432,62.5,7,5"]; model.edits = ["radio":"869.432,62.5,8,5"]
        t.answer = { $0 == "get radio" ? "> 869.432,62.500,8,5" : "OK - reboot to apply" }
        model.save("radio")
        XCTAssertFalse(model.restartRequired); XCTAssertTrue(t.commands.isEmpty); XCTAssertNotNil(model.confirmation)
        let action = model.confirmation?.action; model.confirmation = nil; action?(); try await finished(model)
        XCTAssertTrue(model.restartRequired); XCTAssertTrue(model.dirtyKeys.isEmpty)
        XCTAssertFalse(t.commands.contains("reboot"))
    }
    @MainActor func testRefreshAndNodeSwitchProtectUnsavedEdits() {
        let (model,t) = fixture()
        model.config = ["name":"Before"]; model.edits = ["name":"After"]
        model.readConfig(keys:["name"])
        XCTAssertTrue(t.commands.isEmpty); XCTAssertNotNil(model.confirmation)
        model.confirmation = nil
        let oldID = model.selectedID
        model.selectRepeater("new")
        XCTAssertEqual(model.selectedID,oldID); XCTAssertEqual(model.edits["name"],"After"); XCTAssertNotNil(model.confirmation)
        model.confirmation?.action()
        XCTAssertEqual(model.selectedID,"new"); XCTAssertTrue(model.edits.isEmpty); XCTAssertNil(model.adminID)
    }
    @MainActor func testUnsupportedReadIsNotAnEditableValue() async throws {
        let (model,t) = fixture()
        t.answer = { _ in "Unknown command" }
        model.readConfig(keys:["name"]); try await finished(model)
        XCTAssertNil(model.config["name"]); XCTAssertNil(model.edits["name"])
        XCTAssertEqual(model.fieldStates["name"],.unsupported)
    }
}
