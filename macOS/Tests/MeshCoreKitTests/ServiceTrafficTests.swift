import XCTest
@testable import MeshCoreKit

@MainActor final class ServiceTrafficTests: XCTestCase {
    final class Clock { var date = Date(timeIntervalSince1970:1800000000); var waits: [Double] = [] }
    func governor(_ clock: Clock) -> ServiceTrafficGovernor { ServiceTrafficGovernor(now:{clock.date},delay:{clock.waits.append($0); clock.date.addTimeInterval($0)}) }
    func testPlanBoundsAndRouteClassification() throws {
        XCTAssertEqual(ServiceRoute.classify(path:0),.known)
        XCTAssertEqual(ServiceRoute.classify(path:0x83),.known)
        for path: UInt8 in [255,0xc1,0x7f] { XCTAssertEqual(ServiceRoute.classify(path:path),.floodOrUnknown) }
        XCTAssertEqual(try DiagnosticPlan(route:.known).durationMinutes,720)
        XCTAssertThrowsError(try DiagnosticPlan(intervalMinutes:30,samples:3,route:.floodOrUnknown))
        XCTAssertEqual(try DiagnosticPlan(intervalMinutes:180,samples:6,route:.floodOrUnknown).durationMinutes,1080)
        for count in [0,7,Int.max] { XCTAssertThrowsError(try DiagnosticPlan(intervalMinutes:60,samples:count,route:.known)) }
        XCTAssertThrowsError(try DiagnosticPlan(intervalMinutes:120,samples:4,route:.known))
    }
    func testFiniteSlotsWaitFirstIntervalAndNeverCatchUp() throws {
        let start = Date(timeIntervalSince1970:0), plan = try DiagnosticPlan(route:.known)
        var run = DiagnosticMeasurement(plan:plan,start:start)
        XCTAssertFalse(run.takeDue(now:start,busy:false))
        XCTAssertTrue(run.takeDue(now:start.addingTimeInterval(14400),busy:false)); run.finish(success:true)
        XCTAssertFalse(run.takeDue(now:start.addingTimeInterval(28800),busy:true))
        XCTAssertFalse(run.takeDue(now:start.addingTimeInterval(43300),busy:false))
        XCTAssertEqual(run.received,1); XCTAssertEqual(run.skipped,2); XCTAssertEqual(run.remaining,0); XCTAssertFalse(run.running)
        XCTAssertFalse(run.takeDue(now:start.addingTimeInterval(57600),busy:false))
    }
    func testErrorStopAndInflightStopNeverScheduleAnotherRequest() throws {
        let start = Date(), plan = try DiagnosticPlan(route:.known)
        var run = DiagnosticMeasurement(plan:plan,start:start)
        XCTAssertTrue(run.takeDue(now:run.next!,busy:false)); run.stop(); run.finish(success:true)
        XCTAssertEqual(run.received,1); XCTAssertFalse(run.running); XCTAssertNil(run.next)
        var failed = DiagnosticMeasurement(plan:plan,start:start)
        XCTAssertTrue(failed.takeDue(now:failed.next!,busy:false)); failed.finish(success:false)
        XCTAssertFalse(failed.running); XCTAssertEqual(failed.consumed,1); XCTAssertEqual(failed.received,0)
    }
    func testDefaultFourHourPlanUsesThreeSlotsThroughTwelveHours() throws {
        let start = Date(timeIntervalSince1970:0), plan = try DiagnosticPlan(route:.floodOrUnknown)
        XCTAssertEqual(plan.intervalMinutes,240); XCTAssertEqual(plan.samples,3); XCTAssertEqual(plan.durationMinutes,720)
        var run = DiagnosticMeasurement(plan:plan,start:start)
        XCTAssertEqual(run.next,start.addingTimeInterval(4*3600))
        XCTAssertFalse(run.takeDue(now:start.addingTimeInterval(4*3600-1),busy:false))
        for hour in [4,8,12] {
            XCTAssertEqual(run.next,start.addingTimeInterval(Double(hour*3600)))
            XCTAssertTrue(run.takeDue(now:run.next!,busy:false)); run.finish(success:true)
        }
        XCTAssertFalse(run.running); XCTAssertNil(run.next); XCTAssertEqual(run.received,3)
        XCTAssertFalse(run.takeDue(now:start.addingTimeInterval(24*3600),busy:false))
    }
    func testEveryMinuteAndSampleCombinationObeysTwentyFourHourCap() throws {
        for route: ServiceRoute in [.known,.floodOrUnknown] {
            for minutes in 180...1440 {
                for count in 1...6 {
                    if minutes*count <= 1440 {
                        XCTAssertEqual(try DiagnosticPlan(intervalMinutes:minutes,samples:count,route:route).durationMinutes,minutes*count)
                    } else { XCTAssertThrowsError(try DiagnosticPlan(intervalMinutes:minutes,samples:count,route:route)) }
                }
            }
        }
        for minutes in [Int.min,-1,0,179,1441,Int.max] { XCTAssertThrowsError(try DiagnosticPlan(intervalMinutes:minutes,samples:1,route:.known)) }
        XCTAssertEqual(try DiagnosticPlan(intervalMinutes:1440,samples:1,route:.known).durationMinutes,1440)
        XCTAssertEqual(try DiagnosticPlan(intervalMinutes:240,samples:6,route:.known).durationMinutes,1440)
        XCTAssertThrowsError(try DiagnosticPlan(intervalMinutes:241,samples:6,route:.known))
    }
    func testAllDayMeasurementFinishesAndLateLastSlotIsNeverReplayed() throws {
        let start = Date(timeIntervalSince1970:0), plan = try DiagnosticPlan(intervalMinutes:1440,samples:1,route:.known)
        var run = DiagnosticMeasurement(plan:plan,start:start)
        XCTAssertFalse(run.takeDue(now:start.addingTimeInterval(24*3600-1),busy:false))
        XCTAssertTrue(run.takeDue(now:run.next!,busy:false)); run.finish(success:true)
        XCTAssertFalse(run.running); XCTAssertEqual(run.received,1)
        var late = DiagnosticMeasurement(plan:plan,start:start)
        XCTAssertFalse(late.takeDue(now:start.addingTimeInterval(24*3600+31),busy:false))
        XCTAssertFalse(late.running); XCTAssertEqual(late.skipped,1); XCTAssertNil(late.next)
    }
    func testDiagnosticPreferenceMigrationPreservesValidIntervalsAndIsIdempotent() throws {
        for minutes in [5,30,60,179,180,181,240,360,480,1440] {
            let json = "{\"diagnosticMinutes\":\(minutes),\"diagnosticSamples\":3,\"monitorMinutes\":5,\"suggestions\":false,\"autoReconnect\":false}"
            let options = try JSONDecoder().decode(DevicePreferences.self,from:Data(json.utf8))
            let expected = minutes < 180 ? 240 : minutes
            XCTAssertEqual(options.diagnosticMinutes,expected)
            XCTAssertEqual(options.diagnosticSamples,min(3,1440/expected))
            XCTAssertEqual(options.monitorMinutes,5); XCTAssertFalse(options.autoReconnect); XCTAssertFalse(options.suggestions)
            _ = try DiagnosticPlan(intervalMinutes:options.diagnosticMinutes,samples:options.diagnosticSamples,route:.floodOrUnknown)
            XCTAssertEqual(try JSONDecoder().decode(DevicePreferences.self,from:JSONEncoder().encode(options)),options)
        }
        XCTAssertEqual(DevicePreferences().diagnosticMinutes,240)
        XCTAssertEqual(DiagnosticPlan.hoursText(240),"4 h"); XCTAssertEqual(DiagnosticPlan.hoursText(181),"3 h 1 min")
    }
    func testBudgetsAreSharedAcrossScopesAndSpacingDependsOnRoute() async throws {
        let c = Clock(), g = governor(c)
        for _ in 0..<12 { try g.begin(valid:{true}); try await g.acquire(route:.floodOrUnknown); g.end() }
        XCTAssertEqual(c.waits,Array(repeating:60,count:11))
        do { try await g.acquire(route:.floodOrUnknown); XCTFail("Flood limit not enforced") } catch {}
        try await g.acquire(route:.known)
        c.date.addTimeInterval(3600); try await g.acquire(route:.floodOrUnknown)
    }
    func testGlobalAndMultistepLimitsDoNotQueue() async throws {
        let c = Clock(), g = governor(c)
        try g.begin(valid:{true})
        for _ in 0..<32 { try await g.acquire(route:.known) }
        do { try await g.acquire(route:.known); XCTFail() } catch {}
        g.end()
        for _ in 32..<60 { try await g.acquire(route:.known) }
        do { try await g.acquire(route:.known); XCTFail() } catch {}
        XCTAssertEqual(c.waits.count,59); XCTAssertEqual(c.waits.first,15)
    }
    func testAuthorizationAndDeadlineAreRecheckedAfterWait() async throws {
        let c = Clock(); var valid = true
        let g = ServiceTrafficGovernor(now:{c.date},delay:{c.date.addTimeInterval($0); valid = false})
        try g.begin(valid:{valid}); try await g.acquire(route:.known)
        do { try await g.acquire(route:.known); XCTFail() } catch {}
        g.end(); valid = true; try g.begin(valid:{valid}); c.date.addTimeInterval(1201)
        do { try await g.acquire(route:.known); XCTFail() } catch {}
    }
    func testLocalReadsDoNotSpendCreditsAndReconnectDoesNotResetBudget() async throws {
        let t = FakeTransport(), c = Clock(), s = MeshSession(traffic:governor(c),transport:t)
        t.handle = { f in t.emit(f[0] == 4 ? Data([4,0,0,0,0]) : Data([0])) }
        for _ in 0..<12 { try await s.discover(tag:1) }
        try await s.contacts(); s.reset()
        do { try await s.discover(tag:2); XCTFail() } catch {}
        XCTAssertEqual(t.sent.filter{$0[0] == 55}.count,12); XCTAssertFalse(s.requiresReconnect)
    }
    func testConcurrentCommandDuringPacingIsRejectedWithoutGrowingQueue() async throws {
        let t = FakeTransport(), c = Clock(); var resume: CheckedContinuation<Void,Error>?
        let g = ServiceTrafficGovernor(now:{c.date},delay:{ seconds in try await withCheckedThrowingContinuation { resume = $0 }; c.date.addTimeInterval(seconds) })
        let s = MeshSession(traffic:g,transport:t); t.handle = { _ in t.emit(Data([0])) }
        try await s.discover(tag:1)
        let second = Task { try await s.discover(tag:2) }
        for _ in 0..<100 { if resume != nil { break }; await Task.yield() }
        XCTAssertNotNil(resume)
        do { try await s.contacts(); XCTFail() } catch {}
        XCTAssertEqual(t.sent.count,1); resume?.resume(); try await second.value; XCTAssertEqual(t.sent.count,2)
    }
    func testLegacyPreferencesPreserveOtherValuesButUseNewDefaults() throws {
        let data = Data(#"{"autoReconnect":false,"monitorMinutes":5,"suggestions":false}"#.utf8)
        let options = try JSONDecoder().decode(DevicePreferences.self,from:data)
        XCTAssertEqual(options.monitorMinutes,5); XCTAssertEqual(options.diagnosticMinutes,240); XCTAssertEqual(options.diagnosticSamples,3)
        XCTAssertFalse(options.autoReconnect); XCTAssertFalse(options.suggestions)
        XCTAssertEqual(try JSONDecoder().decode(DevicePreferences.self,from:JSONEncoder().encode(options)),options)
    }
    func testOnlyCompanionContactRoutesCountAndActualFloodInvalidatesThem() async throws {
        let t = FakeTransport(), clock = Clock(), s = MeshSession(traffic:governor(clock),transport:t), key = Data(repeating:0xab,count:32)
        var c = Contact(key:key,kind:2,name:"Test",stored:true); c.outPathLength = 0
        let contact = Data([3])+Data(try MeshCodec.addContact(c).dropFirst())+Data(repeating:0,count:4)
        t.emit(contact); XCTAssertEqual(s.route(for:key),.known)
        t.emit(Data([0x80])+Data(repeating:0xee,count:32)); XCTAssertEqual(s.route(for:key),.known)
        t.emit(Data([0x81])+key); XCTAssertEqual(s.route(for:key),.floodOrUnknown)
        t.emit(contact); t.emit(Data([2,0,0,0,0])); XCTAssertEqual(s.route(for:key),.floodOrUnknown)
        t.emit(contact)
        t.handle = { _ in t.emit(Data([6,1,0,0,0,0,0,0,0,0])); t.emit(Data([0x85,1])+key.prefix(6)) }
        _ = try await s.login(key:key,password:"test")
        XCTAssertEqual(s.route(for:key),.floodOrUnknown)
    }
    func testClockRollbackStopsAndNewRunHasDistinctIdentity() throws {
        let start = Date(), plan = try DiagnosticPlan(route:.known)
        var first = DiagnosticMeasurement(plan:plan,start:start)
        let second = DiagnosticMeasurement(plan:plan,start:start)
        XCTAssertNotEqual(first.id,second.id)
        XCTAssertFalse(first.takeDue(now:start.addingTimeInterval(-1),busy:false)); XCTAssertFalse(first.running)
    }
    func testCLIQueueIsDrainedAfterPacingBeforeNewRequest() async throws {
        let t = FakeTransport(), clock = Clock(), key = Data(repeating:0xab,count:32)
        var queue: [String] = []; var timestamp: UInt32 = 1
        let governor = ServiceTrafficGovernor(now:{clock.date},delay:{ seconds in queue.append("> stale"); clock.date.addTimeInterval(seconds) })
        let session = MeshSession(traffic:governor,transport:t)
        t.handle = { frame in
            if frame[0] == 10 {
                if queue.isEmpty { t.emit(Data([10])) }
                else { var message = Data([7])+key.prefix(6)+Data([255,1]); message.appendLE(timestamp); timestamp += 1; message.append(Data(queue.removeFirst().utf8)); t.emit(message) }
            } else {
                queue.append("> " + String(decoding:frame.dropFirst(13),as:UTF8.self))
                t.emit(Data([6,0,0,0,0,0,0,0,0,0]))
            }
        }
        let first = try await session.cli(key:key,command:"first"), second = try await session.cli(key:key,command:"second")
        XCTAssertEqual(first,"> first"); XCTAssertEqual(second,"> second")
        XCTAssertEqual(t.sent.filter{$0[0] == 2}.count,2)
    }
}
