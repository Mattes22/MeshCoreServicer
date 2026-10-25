import XCTest
import MeshCoreKit
@testable import MeshCoreServicer

@MainActor private final class ChatTransport: MeshTransport {
    var onFrame: ((Data)->Void)?
    var onDisconnect: (()->Void)?
    var sent: [Data] = []
    var handle: ((Data)->Void)?
    func write(_ frame: Data) async throws { sent.append(frame); handle?(frame) }
}
final class MessagesModelTests: XCTestCase {
    private let account = String(repeating:"a",count:64)
    @MainActor func testEarlyACKAndTimeoutNeverConfirmAnotherMessage() async {
        let model = MessagesModel(); await model.activate(account:account)
        var a = ChatRecord(conversationID:"dm:aa",title:"A",outgoing:true,sender:"Me",text:"A",timestamp:1,delivery:.sending)
        a.date = Date().addingTimeInterval(-1)
        model.appendOutgoing(a)
        model.acknowledge(code:42,roundTrip:350)
        model.accepted(id:a.id,receipt:SendReceipt(flood:false,acknowledgement:42,timeout:10))
        XCTAssertEqual(model.records[0].delivery,.acknowledged)
        let b = ChatRecord(conversationID:"dm:bb",title:"B",outgoing:true,sender:"Me",text:"B",timestamp:2,delivery:.sending)
        model.appendOutgoing(b); model.accepted(id:b.id,receipt:SendReceipt(flood:false,acknowledgement:43,timeout:10))
        model.acknowledge(code:999,roundTrip:1)
        XCTAssertEqual(model.records[1].delivery,.awaitingAcknowledgement)
        model.expire(now:Date().addingTimeInterval(5)); XCTAssertEqual(model.records[1].delivery,.unconfirmed)
        model.acknowledge(code:43,roundTrip:5000); XCTAssertEqual(model.records[1].delivery,.acknowledged)
    }
    @MainActor func testChannelAcceptanceAndCapturedForwardingsAreNotDeliveryACKs() async throws {
        let model = MessagesModel(); await model.activate(account:account)
        let channel = try ChannelInfo(index:0,name:"Test",secret:Data(repeating:0,count:16)); model.setChannel(channel)
        let payload = Data([0x37,0xb7,0x3f,0x19,0xaf,0x5f,0x84,0x82,0x36,0x7b,0xdd,0x51,0x8b,0xa3,0x08,0x3a,0x1d,0x70,0xbc])
        let rawZero = try XCTUnwrap(GroupObservation.decode(raw:Data([0x15,0])+payload,rssi:-90,snr:2))
        let rawOne = try XCTUnwrap(GroupObservation.decode(raw:Data([0x15,1,0xaa])+payload,rssi:-80,snr:5))
        model.observe(rawZero); model.observe(rawOne); model.observe(rawOne)
        var frame = Data([8,0,1,0]); frame.appendLE(42); frame.append(Data("Ada: test".utf8))
        guard case .channelMessage(let message) = try MeshCodec.decode(frame) else { return XCTFail() }
        model.receive(message); model.receive(message)
        XCTAssertEqual(model.records.count,1); XCTAssertEqual(model.records[0].hops,1); XCTAssertEqual(model.records[0].capturedForwardings,2)
        model.observe(rawOne); XCTAssertEqual(model.records[0].capturedForwardings,3)
        var outgoing = ChatRecord(conversationID:channel.id,title:channel.name,channelIndex:0,outgoing:true,sender:"Ada",text:"next",timestamp:43,delivery:.sending)
        outgoing.packetFingerprint = try channel.packetFingerprint(timestamp:43,wireText:"Ada: next")
        model.appendOutgoing(outgoing); model.accepted(id:outgoing.id,receipt:nil)
        model.acknowledge(code:0,roundTrip:1)
        XCTAssertEqual(model.records.last?.delivery,.accepted)
    }
    @MainActor func testIncomingCLIIsNotChatAndUnreadIsConversationSpecific() async throws {
        let model = MessagesModel(); await model.activate(account:account)
        func message(_ type: UInt8,_ time: UInt32) throws -> CLIMessage {
            var d = Data([7])+Data(repeating:1,count:6)+Data([255,type]); d.appendLE(time); d.append(Data("Hello".utf8))
            guard case .message(let m) = try MeshCodec.decode(d) else { throw MeshError.invalid("test") }; return m
        }
        model.receive(try message(1,1),contacts:[]); XCTAssertTrue(model.records.isEmpty)
        let m = try message(0,2)
        model.receive(m,contacts:[]); model.receive(m,contacts:[])
        XCTAssertEqual(model.records.count,1); XCTAssertEqual(model.unreadCount,1)
        model.visible = true; model.select("dm:010101010101")
        XCTAssertEqual(model.unreadCount,0)
    }
    @MainActor func testDisconnectMarksPendingAsUnconfirmedAndDoesNotResend() async {
        let model = MessagesModel(); await model.activate(account:account)
        let r = ChatRecord(conversationID:"dm:aa",title:"A",outgoing:true,sender:"Me",text:"A",timestamp:1,delivery:.sending)
        model.appendOutgoing(r); model.disconnected()
        XCTAssertEqual(model.records[0].delivery,.unconfirmed)
        await model.activate(account:account); XCTAssertEqual(model.records.count,1)
    }
    @MainActor func testOrdinaryChatNeverTargetsRepeaterOrRoom() async {
        let t = ChatTransport(), model = AppModel(traffic:.testing(),ble:BluetoothTransport(startImmediately:false),transport:t)
        await model.messages.activate(account:account); model.initialized = true
        for kind: UInt8 in [2,3] {
            let c = Contact(key:Data(repeating:kind,count:32),kind:kind,name:"Not a companion",stored:true)
            model.contacts = [c]; let id = "dm:"+c.key.prefix(6).hex; model.messages.select(id); model.messages.drafts[id] = "reboot"
            model.sendChat(); XCTAssertTrue(t.sent.isEmpty); XCTAssertNotNil(model.error)
        }
    }
    @MainActor func testSendingDMRequiresNoRepeaterAdminAndLogsNoContent() async throws {
        let t = ChatTransport(), model = AppModel(traffic:.testing(),ble:BluetoothTransport(startImmediately:false),transport:t)
        await model.messages.activate(account:account); model.initialized = true
        let c = Contact(key:Data(repeating:1,count:32),kind:1,name:"Peer",stored:true)
        model.contacts = [c]; let id = "dm:"+c.key.prefix(6).hex; model.messages.select(id); model.messages.drafts[id] = "PRIVATE TEST TEXT"
        t.handle = { frame in
            XCTAssertEqual(frame[0],2); XCTAssertEqual(frame[1],0)
            var ack = Data([0x82]); ack.appendLE(77); ack.appendLE(120); t.onFrame?(ack)
            var sent = Data([6,0]); sent.appendLE(77); sent.appendLE(1000); t.onFrame?(sent)
        }
        model.sendChat()
        let end = Date().addingTimeInterval(2)
        while model.busy && Date() < end { try await Task.sleep(nanoseconds:1_000_000) }
        XCTAssertFalse(model.busy); XCTAssertEqual(t.sent.count,1); XCTAssertEqual(model.messages.records.first?.delivery,.acknowledged)
        XCTAssertFalse(model.logs.contains { $0.text.contains("PRIVATE TEST TEXT") }); XCTAssertEqual(model.messages.drafts[id],"")
    }
    @MainActor func testOwnChannelEchoDoesNotCreateAnotherMessageOrCountAsACK() async throws {
        let model = MessagesModel(); await model.activate(account:account)
        let c = try ChannelInfo(index:0,name:"Test",secret:Data(repeating:0,count:16)); model.setChannel(c)
        var outgoing = ChatRecord(conversationID:c.id,title:c.name,channelIndex:0,outgoing:true,sender:"Ada",text:"test",timestamp:42,delivery:.sending)
        outgoing.packetFingerprint = try c.packetFingerprint(timestamp:42,wireText:"Ada: test"); outgoing.capturedForwardings = 0
        model.appendOutgoing(outgoing); model.accepted(id:outgoing.id,receipt:nil)
        var d = Data([8,0,2,0]); d.appendLE(42); d.append(Data("Ada: test".utf8))
        guard case .channelMessage(let m) = try MeshCodec.decode(d) else { return XCTFail() }
        model.receive(m)
        XCTAssertEqual(model.records.count,1); XCTAssertEqual(model.records[0].capturedForwardings,0); XCTAssertEqual(model.records[0].delivery,.accepted)
    }
    @MainActor func testChangingChannelKeySeparatesConversationIdentity() async throws {
        let model = MessagesModel(); await model.activate(account:account)
        let a = try ChannelInfo(index:0,name:"Same name",secret:Data(repeating:0,count:16)), b = try ChannelInfo(index:0,name:"Same name",secret:Data(repeating:1,count:16))
        func frame(_ timestamp: UInt32) throws -> ChannelMessage {
            var d = Data([8,0,0,0]); d.appendLE(timestamp); d.append(Data("Ada: text".utf8))
            guard case .channelMessage(let m) = try MeshCodec.decode(d) else { throw MeshError.invalid("fixture") }; return m
        }
        model.setChannel(a); model.receive(try frame(1)); model.setChannel(b); model.receive(try frame(2))
        XCTAssertNotEqual(model.records[0].conversationID,model.records[1].conversationID)
        XCTAssertNotEqual(model.records[0].packetFingerprint,model.records[1].packetFingerprint)
    }
    @MainActor func testACKCollisionNeverConfirmsTheNewMessage() async {
        let model = MessagesModel(); await model.activate(account:account)
        let a = ChatRecord(conversationID:"dm:a",title:"A",outgoing:true,sender:"Me",text:"A",timestamp:1,delivery:.sending)
        model.appendOutgoing(a); model.accepted(id:a.id,receipt:SendReceipt(flood:false,acknowledgement:42,timeout:1)); model.acknowledge(code:42,roundTrip:100)
        let b = ChatRecord(conversationID:"dm:b",title:"B",outgoing:true,sender:"Me",text:"B",timestamp:2,delivery:.sending)
        model.appendOutgoing(b); model.acknowledge(code:42,roundTrip:200)
        model.accepted(id:b.id,receipt:SendReceipt(flood:false,acknowledgement:42,timeout:1)); model.acknowledge(code:42,roundTrip:300)
        XCTAssertEqual(model.records[0].delivery,.acknowledged); XCTAssertEqual(model.records[1].delivery,.unconfirmed); XCTAssertNil(model.records[1].acknowledgement)
    }
    func testArchiveIsolatesCompanionsAndIgnoresStaleSnapshots() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let archive = ChatArchive(folder:folder)
        let r = ChatRecord(conversationID:"dm:aa",title:"A",outgoing:false,sender:"Peer",text:"Saved",timestamp:1,delivery:.received)
        try await archive.save([r],account:account,revision:2)
        try await archive.save([],account:account,revision:1)
        let loaded = try await archive.load(account:account), other = try await archive.load(account:String(repeating:"b",count:64))
        XCTAssertEqual(loaded,[r]); XCTAssertTrue(other.isEmpty)
        let text = try String(contentsOf:folder.appendingPathComponent(account+".json"))
        XCTAssertFalse(text.contains("secret"))
    }
    @MainActor func testCorruptHistoryIsNotOverwritten() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let file = folder.appendingPathComponent(account+".json"); try Data("broken".utf8).write(to:file)
        let model = MessagesModel(archive:ChatArchive(folder:folder)); await model.activate(account:account)
        model.appendOutgoing(ChatRecord(conversationID:"dm:aa",title:"A",outgoing:true,sender:"Me",text:"New",timestamp:2,delivery:.sending))
        await model.flush(); XCTAssertNotNil(model.storageError); XCTAssertEqual(try String(contentsOf:file),"broken")
    }
}
