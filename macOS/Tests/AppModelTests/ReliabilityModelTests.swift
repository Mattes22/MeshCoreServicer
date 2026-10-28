import XCTest
import MeshCoreKit
@testable import MeshCoreServicer

final class ReliabilityModelTests: XCTestCase {
    @MainActor func testConsolePreferencesDefaultsPersistWithoutCommandsOrSecrets() throws {
        let suite = "MeshCoreServicerTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let p = AppPreferences(defaults:defaults)
        XCTAssertTrue(p.consoleSuggestions); XCTAssertTrue(p.consoleHelp); XCTAssertTrue(p.consoleHistory)
        XCTAssertFalse(p.consoleChanges); XCTAssertTrue(p.consoleEnterSends)
        p.consoleSuggestions = false; p.consoleHelp = false; p.consoleHistory = false
        p.consoleChanges = true; p.consoleEnterSends = false
        let loaded = AppPreferences(defaults:defaults)
        XCTAssertFalse(loaded.consoleSuggestions); XCTAssertFalse(loaded.consoleHelp); XCTAssertFalse(loaded.consoleHistory)
        XCTAssertTrue(loaded.consoleChanges); XCTAssertFalse(loaded.consoleEnterSends)
        XCTAssertEqual(Set(defaults.persistentDomain(forName:suite)!.keys),["consoleSuggestions","consoleHelp","consoleHistory","consoleChanges","consoleEnterSends","autoReconnect","notifications","notificationSound","notificationText","mutedConversations"])
    }
    private let account = String(repeating:"11",count:32), repeater = String(repeating:"ab",count:32)
    private func status(_ uptime: UInt32 = 600,battery: UInt16 = 3700) throws -> RepeaterStatus {
        try RepeaterStatus.decode(statusData(uptime,battery:battery))
    }
    private func statusData(_ uptime: UInt32 = 600,battery: UInt16 = 3700) -> Data {
        var d = Data([UInt8(truncatingIfNeeded:battery),UInt8(battery >> 8),0,0,0x88,0xff,0x9c,0xff])
        for n: UInt32 in [10,20,30,uptime,1,2,3,4] { d.appendLE(n) }; d.append(contentsOf:[0,0,8,0,0,0,0,0]); return d
    }
    @MainActor private func fixture(traffic: ServiceTrafficGovernor? = nil) async throws -> (AppModel,ToolsTransport,Contact) {
        let t = ToolsTransport(), m = AppModel(traffic:traffic ?? .testing(),ble:BluetoothTransport(startImmediately:false),transport:t)
        let c = Contact(key:Data(repeating:0xab,count:32),kind:2,name:"Test",stored:true)
        m.contacts = [c]; m.selectedID = c.id; m.initialized = true; m.adminID = c.id
        var info = Data([5,0,0,0])+Data(repeating:0x11,count:32)+Data(repeating:0,count:12); info.appendLE(869432); info.appendLE(62500); info.append(contentsOf:[7,5]); info.append(Data("Self".utf8)); m.event(try MeshCodec.decode(info))
        await m.operations.activate(account:account); m.operations.select(c.id)
        return (m,t,c)
    }
    @MainActor private func finish(_ m: AppModel) async throws { for _ in 0..<2000 { if !m.busy { return }; try await Task.sleep(nanoseconds:1_000_000) }; XCTFail("Operation stuck") }
    @MainActor private func confirm(_ m: AppModel) { let action = m.confirmation?.action; m.confirmation = nil; action?() }
    @MainActor func testNotificationsHideContentByDefaultAndRespectMuteAccountAndHistory() {
        let prefs = AppPreferences()
        let r = ChatRecord(conversationID:"channel:0:hash",title:"Private channel",channelIndex:0,outgoing:false,sender:"Peer",text:"SECRET TEXT",timestamp:1,delivery:.received)
        XCTAssertNil(MessageNotification.make(r,account:account,preferences:prefs,live:true))
        prefs.notifications = true
        XCTAssertNil(MessageNotification.make(r,account:account,preferences:prefs,live:false))
        let notice = MessageNotification.make(r,account:account,preferences:prefs,live:true)
        XCTAssertFalse(notice!.body.contains("SECRET")); XCTAssertFalse(notice!.title.contains("Private"))
        prefs.mute(true,account:account,conversation:r.conversationID)
        XCTAssertNil(MessageNotification.make(r,account:account,preferences:prefs,live:true))
        XCTAssertNotNil(MessageNotification.make(r,account:String(repeating:"2",count:64),preferences:prefs,live:true))
        prefs.mute(false,account:account,conversation:r.conversationID); prefs.showMessageText = true
        XCTAssertEqual(MessageNotification.make(r,account:account,preferences:prefs,live:true)?.body,"SECRET TEXT")
        var read = r; read.seen = true; XCTAssertNil(MessageNotification.make(read,account:account,preferences:prefs,live:true))
        let outgoing = ChatRecord(conversationID:r.conversationID,title:"Test",outgoing:true,sender:"Me",text:"Text",timestamp:1,delivery:.accepted)
        XCTAssertNil(MessageNotification.make(outgoing,account:account,preferences:prefs,live:true))
    }
    @MainActor func testMinimizedConversationDoesNotMarkMessagesReadAndDuplicateDoesNotNotifyAgain() async throws {
        let m = MessagesModel(); await m.activate(account:account); m.visible = true; m.readingAllowed = false; m.select("dm:010101010101")
        var notifications = 0; m.onIncoming = {_ in notifications += 1}
        var raw = Data([7])+Data(repeating:1,count:6)+Data([255,0]); raw.appendLE(1); raw.append(Data("Text".utf8))
        guard case .message(let message) = try MeshCodec.decode(raw) else { return XCTFail() }
        m.receive(message,contacts:[]); m.receive(message,contacts:[])
        XCTAssertEqual(m.unreadCount,1); XCTAssertEqual(notifications,1)
        m.markRead(); XCTAssertEqual(m.unreadCount,1)
        m.readingAllowed = true; m.markRead(); XCTAssertEqual(m.unreadCount,0)
    }
    @MainActor func testCapturedCopiesRetainPerPacketMetricsWithBoundedDetail() async throws {
        let m = MessagesModel(); await m.activate(account:account)
        let channel = try ChannelInfo(index:0,name:"Test",secret:Data(repeating:0,count:16)); m.setChannel(channel)
        let payload = Data([0x37,0xb7,0x3f,0x19,0xaf,0x5f,0x84,0x82,0x36,0x7b,0xdd,0x51,0x8b,0xa3,0x08,0x3a,0x1d,0x70,0xbc])
        let one = try XCTUnwrap(GroupObservation.decode(raw:Data([0x15,1,0xaa])+payload,rssi:-81,snr:4.5))
        m.observe(one)
        var raw = Data([8,0,1,0]); raw.appendLE(42); raw.append(Data("Ada: test".utf8))
        guard case .channelMessage(let message) = try MeshCodec.decode(raw) else { return XCTFail() }
        m.receive(message)
        for _ in 0..<64 { m.observe(one) }; m.receive(message)
        XCTAssertEqual(m.records.count,1); XCTAssertEqual(m.records[0].capturedForwardings,65); XCTAssertEqual(m.records[0].captures?.count,64)
        XCTAssertEqual(m.records[0].captures?.first?.rssi,-81); XCTAssertEqual(m.records[0].captures?.first?.snr,4.5)
        XCTAssertEqual(m.records[0].delivery,.received)
    }
    @MainActor func testSnapshotCaptureOmitsSecretsAndUnverifiedFieldsAndDoesNotTransmit() async throws {
        let (m,t,c) = try await fixture()
        m.config = ["name":"Good","tx":"17","guest.password":"SECRET","prv.key":"SECRET"]
        m.configDates = m.config.mapValues{_ in Date()}; m.operations.beginChange("tx",repeater:c.id)
        m.captureSnapshot(name:"Before")
        XCTAssertTrue(t.frames.isEmpty); XCTAssertEqual(m.operations.current.snapshots.first?.values,["name":"Good"])
    }
    @MainActor func testRestoreRequiresFreshComparisonAndConfirmationThenReadback() async throws {
        let (m,t,_) = try await fixture(); t.values["name"] = "Old"
        let snapshot = try ConfigSnapshot(account:account,repeater:repeater,name:"Test",values:["name":"New"])
        m.compareSnapshot(snapshot,keys:["name"]); try await finish(m)
        XCTAssertEqual(t.commands,["get name"]); XCTAssertEqual(m.restorePreview?.proposed,["name":"New"])
        m.restoreSnapshot(); XCTAssertEqual(t.commands,["get name"]); XCTAssertNotNil(m.confirmation)
        confirm(m); try await finish(m)
        XCTAssertEqual(t.commands,["get name","get name","set name New","get name"])
        XCTAssertTrue(m.operations.current.unverified.isEmpty); XCTAssertNil(m.restorePreview)
    }
    @MainActor func testExternalChangeAfterComparisonPreventsEveryWrite() async throws {
        let (m,t,_) = try await fixture(); t.values["name"] = "Old"
        let s = try ConfigSnapshot(account:account,repeater:repeater,name:"Test",values:["name":"New"])
        m.compareSnapshot(s,keys:["name"]); try await finish(m); t.values["name"] = "External"
        m.restoreSnapshot(); confirm(m); try await finish(m)
        XCTAssertEqual(t.commands,["get name","get name"]); XCTAssertNotNil(m.error)
    }
    @MainActor func testRestoreCannotTargetDifferentIdentityOrReplaceDirtyEdits() async throws {
        let (m,t,_) = try await fixture()
        let wrong = try ConfigSnapshot(account:String(repeating:"2",count:64),repeater:repeater,name:"Test",values:["name":"New"])
        m.compareSnapshot(wrong,keys:["name"]); XCTAssertNotNil(m.error); XCTAssertTrue(t.frames.isEmpty)
        let valid = try ConfigSnapshot(account:account,repeater:repeater,name:"Test",values:["name":"New"])
        m.config = ["name":"Old"]; m.edits = ["name":"Draft"]
        m.compareSnapshot(valid,keys:["name"]); XCTAssertTrue(t.frames.isEmpty); XCTAssertEqual(m.edits["name"],"Draft")
    }
    @MainActor func testFailedConfigWriteRemainsInUnverifiedHistory() async throws {
        let (m,t,c) = try await fixture(); m.config = ["name":"Old"]; m.edits = ["name":"New"]
        t.reply = {$0.hasPrefix("set ") ? "Error" : nil}
        m.save("name"); try await finish(m)
        XCTAssertEqual(m.operations.current.unverified.map(\.key),["name"])
        m.operations.verifiedChange("name",repeater:c.id); XCTAssertTrue(m.operations.current.unverified.isEmpty)
    }
    @MainActor func testMonitoringIsOptInWaitsFirstIntervalAndStopsOnSelectionChange() async throws {
        let (m,t,_) = try await fixture()
        XCTAssertFalse(m.monitoring); XCTAssertTrue(t.frames.isEmpty)
        m.monitorIntervalMinutes = 240; m.setMonitoring(true); await Task.yield()
        XCTAssertTrue(m.monitoring); XCTAssertTrue(t.frames.isEmpty); XCTAssertNotNil(m.monitorNext)
        m.selectedID = "other"; XCTAssertFalse(m.monitoring); XCTAssertNil(m.monitorNext); XCTAssertTrue(t.frames.isEmpty)
    }
    @MainActor func testDefaultModelWaitsFourHoursAndCompletesAtTwelveWithoutExtraTraffic() async throws {
        let (m,t,c) = try await fixture(); t.statusReply = statusData()
        XCTAssertEqual(m.monitorIntervalMinutes,240); XCTAssertEqual(m.monitorSampleLimit,3)
        m.setMonitoring(true); defer { m.stopMonitoring() }
        let start = try XCTUnwrap(m.measurement?.start)
        XCTAssertEqual(m.monitorNext,start.addingTimeInterval(4*3600))
        await m.monitorTick(contact:c,now:start.addingTimeInterval(4*3600-1)); XCTAssertTrue(t.frames.isEmpty)
        for hour in [4,8,12] { await m.monitorTick(contact:c,now:start.addingTimeInterval(Double(hour*3600))) }
        XCTAssertFalse(m.monitoring); XCTAssertNil(m.monitorNext); XCTAssertEqual(m.measurement?.received,3)
        XCTAssertEqual(t.frames.map{$0[0]},[27,27,27]); XCTAssertEqual(m.operations.current.samples.count,3)
        await m.monitorTick(contact:c,now:start.addingTimeInterval(24*3600))
        _ = m.operations.current.samples; XCTAssertEqual(t.frames.count,3)
    }
    @MainActor func testInvalidShortOrOverlongModelPlanCannotStart() async throws {
        let (m,t,_) = try await fixture()
        for (minutes,count) in [(179,3),(300,6),(1440,2)] {
            m.monitorIntervalMinutes = minutes; m.monitorSampleLimit = count; m.setMonitoring(true)
            XCTAssertFalse(m.monitoring); XCTAssertNil(m.measurement); XCTAssertNotNil(m.error)
        }
        XCTAssertTrue(t.frames.isEmpty)
    }
    @MainActor func testMonitorTickSkipsBusyAndStoresOnlyActualReply() async throws {
        let (m,t,c) = try await fixture(); t.statusReply = statusData()
        m.setMonitoring(true); defer { m.stopMonitoring() }
        m.busy = true; await m.monitorTick(contact:c,now:m.measurement!.next!); XCTAssertTrue(t.frames.isEmpty); XCTAssertTrue(m.operations.current.samples.isEmpty)
        m.busy = false; await m.monitorTick(contact:c,now:m.measurement!.next!)
        XCTAssertEqual(t.frames.map{$0[0]},[27]); XCTAssertEqual(m.operations.current.samples.first?.battery,3700)
    }
    @MainActor func testMonitorFailureStopsWithoutRetryingAndDisconnectClearsOptIn() async throws {
        let (m,t,c) = try await fixture(); t.failStatus = true
        m.setMonitoring(true); await m.monitorTick(contact:c,now:m.measurement!.next!)
        XCTAssertFalse(m.monitoring); XCTAssertNotNil(m.error); XCTAssertEqual(t.frames.count,1)
        m.ble.onDisconnect?(); XCTAssertFalse(m.monitoring); XCTAssertFalse(m.liveNotifications)
    }
    @MainActor func testUptimeDropStartsReviewAndClockCheckIsSeparate() async throws {
        let m = OperationsModel(); await m.activate(account:account); m.select(repeater)
        m.record(try status(600),repeater:repeater,date:Date().addingTimeInterval(-600))
        m.record(try status(10),repeater:repeater)
        XCTAssertNotNil(m.current.restart); XCTAssertNotNil(m.current.restart?.reachable); XCTAssertNil(m.current.restart?.clockChecked)
        m.clockChecked(repeater:repeater,text:"12:34 - 1/1/2020 UTC"); XCTAssertNil(m.current.restart?.clockChecked)
        let f = DateFormatter(); f.locale = Locale(identifier:"en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT:0); f.dateFormat = "HH:mm - d/M/yyyy 'UTC'"
        m.clockChecked(repeater:repeater,text:f.string(from:Date())); XCTAssertNotNil(m.current.restart?.clockChecked)
    }
    @MainActor func testRestartRequestDoesNotClaimReachabilityOrClockVerification() async throws {
        let (m,t,_) = try await fixture(); m.sendCLI("reboot")
        XCTAssertTrue(t.frames.isEmpty); confirm(m); try await finish(m)
        XCTAssertNotNil(m.operations.current.restart); XCTAssertNil(m.operations.current.restart?.reachable); XCTAssertNil(m.operations.current.restart?.clockChecked)
        XCTAssertEqual(m.operations.current.unverified.map(\.key),["Restart"])
    }
    @MainActor func testOperationsArchiveIsolatesAccountsAndRestoresPendingReview() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at:folder) }
        let archive = OperationsArchive(folder:folder), m = OperationsModel(archive:archive)
        await m.activate(account:account); m.select(repeater); m.record(try status(),repeater:repeater); m.restartRequested(repeater:repeater); m.beginChange("radio",repeater:repeater)
        try m.addSnapshot(ConfigSnapshot(account:account,repeater:repeater,name:"Test",values:["name":"Good"]))
        await m.flush()
        let restored = OperationsModel(archive:archive); await restored.activate(account:account); restored.select(repeater)
        XCTAssertEqual(restored.current.samples.count,1); XCTAssertEqual(restored.current.unverified.map(\.key),["radio"]); XCTAssertEqual(restored.current.snapshots.count,1)
        await restored.activate(account:String(repeating:"2",count:64)); XCTAssertTrue(restored.current.samples.isEmpty)
    }
    @MainActor func testCorruptOperationsArchiveIsNeverSilentlyOverwritten() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at:folder) }
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let file = folder.appendingPathComponent(account+".json"); try Data("broken".utf8).write(to:file)
        let m = OperationsModel(archive:OperationsArchive(folder:folder)); await m.activate(account:account); m.beginChange("radio",repeater:repeater); await m.flush()
        XCTAssertNotNil(m.storageError); XCTAssertEqual(try String(contentsOf:file),"broken")
    }
    @MainActor func testDiagnosticLimitAndBusySlotsCannotCreateExtraRequests() async throws {
        let (m,t,c) = try await fixture(); t.statusReply = statusData(); m.monitorSampleLimit = 2
        m.setMonitoring(true); XCTAssertEqual(m.measurement?.plan.intervalMinutes,240)
        m.busy = true; await m.monitorTick(contact:c,now:m.measurement!.next!)
        XCTAssertEqual(m.measurement?.skipped,1); m.busy = false
        await m.monitorTick(contact:c,now:m.measurement!.next!)
        XCTAssertFalse(m.monitoring); XCTAssertNil(m.monitorNext); XCTAssertEqual(m.measurement?.received,1)
        await m.monitorTick(contact:c,now:Date().addingTimeInterval(100000))
        XCTAssertEqual(t.frames.filter{$0[0] == 27}.count,1)
    }
    @MainActor func testLateDiagnosticsNeverCatchUpAndHistoryDoesNotTransmit() async throws {
        let (m,t,c) = try await fixture(); m.setMonitoring(true)
        let end = m.measurement!.start.addingTimeInterval(Double(m.measurement!.plan.durationMinutes*60+31))
        await m.monitorTick(contact:c,now:end)
        XCTAssertFalse(m.monitoring); XCTAssertEqual(m.measurement?.skipped,3); XCTAssertTrue(t.frames.isEmpty)
        _ = m.operations.current.samples; m.operations.select(c.id); _ = m.operations.current.snapshots
        XCTAssertTrue(t.frames.isEmpty)
    }
    @MainActor func testRevokedAdminStopsDiagnosticsWithoutAnotherSample() async throws {
        let (m,t,c) = try await fixture(); m.setMonitoring(true)
        m.event(.login(prefix:Data(c.key.prefix(6)),permissions:0))
        XCTAssertFalse(m.monitoring); XCTAssertFalse(m.admin); XCTAssertTrue(t.frames.isEmpty)
    }
    @MainActor func testNewApplicationNeverRestoresAnActiveMeasurement() async throws {
        let (m,t,_) = try await fixture(); m.setMonitoring(true)
        let other = AppModel(traffic:.testing(),ble:BluetoothTransport(startImmediately:false),transport:ToolsTransport(),library:m.library)
        XCTAssertFalse(other.monitoring); XCTAssertNil(other.measurement); XCTAssertTrue(t.frames.isEmpty)
        m.stopMonitoring()
    }
    @MainActor func testStopCancelsPacingBeforeAnyRadioFrame() async throws {
        var waiting = false
        let governor = ServiceTrafficGovernor(now:{Date(timeIntervalSince1970:1800000000)},delay:{ _ in waiting = true; try await Task.sleep(nanoseconds:3_600_000_000_000) })
        try await governor.acquire(route:.floodOrUnknown)
        let (m,t,c) = try await fixture(traffic:governor); m.setMonitoring(true)
        m.monitorTask?.cancel()
        let now = m.measurement!.next!
        let tick = Task { await m.monitorTick(contact:c,now:now) }; m.monitorTask = tick
        for _ in 0..<1000 { if waiting { break }; await Task.yield() }
        XCTAssertTrue(waiting); XCTAssertFalse(m.measurement!.transmitted)
        m.stopMonitoring(); await tick.value
        XCTAssertFalse(m.monitoring); XCTAssertFalse(m.busy); XCTAssertTrue(t.frames.isEmpty); XCTAssertNil(m.error)
    }
}
