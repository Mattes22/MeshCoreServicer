import Foundation
import Combine
import MeshCoreKit

@MainActor final class MessagesModel: ObservableObject {
    @Published private(set) var records: [ChatRecord] = []
    @Published private(set) var channels: [UInt8:ChannelInfo] = [:]
    @Published private(set) var account: String?
    @Published private(set) var storageError: String?
    @Published var syncError: String?
    @Published var selectedConversation: String?
    @Published var drafts: [String:String] = [:]
    var visible = false
    var readingAllowed = true
    var onIncoming: ((ChatRecord)->Void)?
    private let archive: ChatArchive?
    private var writable = true
    private var revision: UInt64 = 0
    private var persistenceTask: Task<Void,Never>?
    private var seen: Set<String> = []
    private var lastTimestamp: UInt32 = 0
    private var deliveryTask: Task<Void,Never>?
    private var earlyACKs: [UInt32:(UInt32,Date)] = [:]
    private struct Observation { var count = 0; var date = Date(); var rssi: Int8; var snr: Double; var captures: [PacketCapture] = [] }
    private var observations: [String:Observation] = [:]
    init(archive: ChatArchive? = nil) { self.archive = archive }
    var unreadCount: Int { records.filter { !$0.outgoing && !$0.seen }.count }
    func activate(account: String) async {
        guard self.account != account else { return }
        self.account = account; records = []; channels = [:]; seen = []; drafts = [:]; observations = [:]; earlyACKs = [:]; writable = true; storageError = nil; selectedConversation = nil
        do {
            let saved = try await archive?.load(account:account) ?? []
            guard self.account == account else { return }
            records = saved
            for i in records.indices where records[i].outgoing && [.sending,.awaitingAcknowledgement].contains(records[i].delivery) {
                records[i].delivery = .unconfirmed; records[i].deadline = nil; records[i].detail = "Předchozí relace skončila bez ověření doručení."
            }
            seen = Set(records.compactMap(\.deduplicationID)); lastTimestamp = records.filter(\.outgoing).map(\.timestamp).max() ?? 0
        } catch { guard self.account == account else { return }; writable = false; storageError = "Historii se nepodařilo načíst. Původní soubor nebude přepsán." }
    }
    func disconnected() {
        for i in records.indices where records[i].outgoing && [.sending,.awaitingAcknowledgement].contains(records[i].delivery) {
            records[i].delivery = .unconfirmed; records[i].detail = "Spojení skončilo bez potvrzení doručení."; records[i].deadline = nil
        }
        deliveryTask?.cancel(); deliveryTask = nil
        persist(); channels = [:]; observations = [:]; earlyACKs = [:]; syncError = nil
    }
    func setChannel(_ c: ChannelInfo) { channels[c.index] = c }
    func finishChannelRefresh(indices: Set<UInt8>) { channels = channels.filter { indices.contains($0.key) } }
    func select(_ id: String?) { selectedConversation = id; markRead() }
    func markRead() {
        guard visible, readingAllowed, let id = selectedConversation else { return }
        var changed = false
        for i in records.indices where records[i].conversationID == id && !records[i].seen { records[i].seen = true; changed = true }
        if changed { persist() }
    }
    func nextTimestamp() -> UInt32 {
        let now = UInt32(clamping:Int64(Date().timeIntervalSince1970))
        lastTimestamp = max(now,lastTimestamp == .max ? now : lastTimestamp + 1); return lastTimestamp
    }
    func appendOutgoing(_ record: ChatRecord) { records.append(record); trim(); persist() }
    func accepted(id: UUID, receipt: SendReceipt?) {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        if let receipt, receipt.acknowledgement != 0 {
            if records.enumerated().contains(where:{ $0.offset != i && $0.element.acknowledgement == receipt.acknowledgement }) {
                records[i].delivery = .unconfirmed; records[i].detail = "ACK kód koliduje s jinou uloženou zprávou; doručení nelze jednoznačně přiřadit."; persist(); return
            }
            records[i].acknowledgement = receipt.acknowledgement
            records[i].delivery = .awaitingAcknowledgement
            records[i].deadline = Date().addingTimeInterval(max(1,Double(receipt.timeout)/1000)+3)
            if let (trip,date) = earlyACKs[receipt.acknowledgement], date >= records[i].date, records.filter({ $0.acknowledgement == receipt.acknowledgement && [.awaitingAcknowledgement,.unconfirmed].contains($0.delivery) }).count == 1 { records[i].delivery = .acknowledged; records[i].roundTrip = trip; records[i].deadline = nil }
        } else { records[i].delivery = .accepted }
        persist(); scheduleExpiration()
    }
    private func scheduleExpiration() {
        guard deliveryTask == nil, records.contains(where:{ $0.delivery == .awaitingAcknowledgement }) else { return }
        deliveryTask = Task { [weak self] in
            defer { self?.deliveryTask = nil }
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds:500_000_000) } catch { break }
                guard let self else { return }
                self.expire()
                if !self.records.contains(where:{ $0.delivery == .awaitingAcknowledgement }) { break }
            }
        }
    }
    func sendFailed(id: UUID, rejected: Bool) {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        records[i].delivery = rejected ? .rejected : .unconfirmed
        records[i].detail = rejected ? "Požadavek companion odmítl." : "Výsledek odeslání není známý. Před dalším odesláním zvažte možnost duplicity."
        persist()
    }
    func acknowledge(code: UInt32, roundTrip: UInt32) {
        earlyACKs = earlyACKs.filter { $0.value.1 > Date().addingTimeInterval(-180) }
        let matching = records.indices.filter { records[$0].outgoing && records[$0].channelIndex == nil && records[$0].acknowledgement == code && [.awaitingAcknowledgement,.unconfirmed].contains(records[$0].delivery) }
        guard matching.count == 1, let i = matching.first else {
            if matching.isEmpty && !records.contains(where:{ $0.acknowledgement == code }) { earlyACKs[code] = (roundTrip,Date()) }
            return
        }
        earlyACKs[code] = nil
        records[i].delivery = .acknowledged; records[i].roundTrip = roundTrip; records[i].deadline = nil; records[i].detail = nil; persist()
    }
    func expire(now: Date = Date()) {
        var changed = false
        for i in records.indices where records[i].delivery == .awaitingAcknowledgement && (records[i].deadline ?? .distantFuture) <= now {
            records[i].delivery = .unconfirmed; records[i].detail = "Potvrzení protějšku v časovém limitu nepřišlo."; records[i].deadline = nil; changed = true
        }
        if changed { persist() }
    }
    func receive(_ m: CLIMessage, contacts: [Contact]) {
        guard account != nil, m.type == 0 || m.type == 2, seen.insert(m.identity).inserted else { return }
        let prefix = m.prefix.hex, matches = contacts.filter { $0.key.prefix(6) == m.prefix }
        let title = matches.count == 1 ? matches[0].name : "Kontakt \(prefix)"
        var r = ChatRecord(conversationID:"dm:"+prefix,title:title,peerPrefix:prefix,outgoing:false,sender:m.senderPrefix.map { "Autor \($0.hex)" } ?? title,text:m.text,timestamp:m.timestamp,delivery:.received)
        r.snr = m.snr; r.hops = MeshMessaging.hops(m.pathLength); r.deduplicationID = m.identity
        r.seen = visible && readingAllowed && selectedConversation == r.conversationID
        records.append(r); trim(); persist(); onIncoming?(r)
    }
    func receive(_ m: ChannelMessage) {
        guard account != nil, m.type == 0, seen.insert(m.identity).inserted else { return }
        let c = channels[m.index]
        let id = c?.id ?? "channel:\(m.index):unknown", title = c?.displayName ?? "Kanál \(m.index)"
        var sender = "Jméno neuvedeno", text = m.text
        if let range = m.text.range(of:": "), m.text[..<range.lowerBound].utf8.count <= 31 { sender = String(m.text[..<range.lowerBound]); text = String(m.text[range.upperBound...]) }
        var r = ChatRecord(conversationID:id,title:title,channelIndex:m.index,outgoing:false,sender:sender,text:text,timestamp:m.timestamp,delivery:.received)
        r.snr = m.snr; r.hops = m.hops; r.deduplicationID = m.identity
        r.packetFingerprint = try? c?.packetFingerprint(timestamp:m.timestamp,wireText:m.text)
        if let fingerprint = r.packetFingerprint, let i = records.firstIndex(where:{ $0.outgoing && $0.packetFingerprint == fingerprint }) {
            records[i].hops = m.hops; records[i].snr = m.snr; persist(); return
        }
        r.capturedForwardings = r.packetFingerprint == nil ? nil : 0
        if let fingerprint = r.packetFingerprint, let obs = observations[fingerprint] { apply(obs,to:&r) }
        r.seen = visible && readingAllowed && selectedConversation == id
        records.append(r); trim(); persist(); onIncoming?(r)
    }
    func observe(_ observation: GroupObservation) {
        guard account != nil else { return }
        let now = Date()
        let capture = PacketCapture(date:now,hops:observation.hops,rssi:observation.rssi,snr:observation.snr)
        if observations.count >= 512 { observations = observations.filter { $0.value.date > now.addingTimeInterval(-300) }; if observations.count >= 512, let key = observations.min(by:{ $0.value.date < $1.value.date })?.key { observations[key] = nil } }
        var value = observations[observation.fingerprint] ?? Observation(rssi:observation.rssi,snr:observation.snr)
        if let hops = observation.hops, hops > 0 { value.count += 1 }
        value.captures.append(capture); value.captures = Array(value.captures.suffix(64))
        value.date = now; value.rssi = observation.rssi; value.snr = observation.snr; observations[observation.fingerprint] = value
        var changed = false
        for i in records.indices where records[i].packetFingerprint == observation.fingerprint {
            // Each raw callback is one RF reception. Replay of a queued message does not count.
            records[i].capturedForwardings = (records[i].capturedForwardings ?? 0) + ((observation.hops ?? 0) > 0 ? 1 : 0)
            records[i].captures = Array(((records[i].captures ?? []) + [capture]).suffix(64))
            records[i].lastObservation = now; records[i].observedRSSI = observation.rssi; records[i].observedSNR = observation.snr; changed = true
        }
        if changed { persist() }
    }
    private func apply(_ o: Observation,to record: inout ChatRecord) { record.captures = o.captures; record.capturedForwardings = o.count; record.lastObservation = o.date; record.observedRSSI = o.rssi; record.observedSNR = o.snr }
    private func trim() { if records.count > 5000 { records.removeFirst(records.count-5000) }; seen = Set(records.compactMap(\.deduplicationID)) }
    func flush() async { await persistenceTask?.value }
    private func persist() {
        guard writable, let account, let archive else { return }
        revision += 1; let revision = revision, snapshot = records
        persistenceTask = Task { [weak self] in
            do { try await archive.save(snapshot,account:account,revision:revision) }
            catch { guard self?.account == account else { return }; self?.storageError = "Historii se nepodařilo uložit na disk." }
        }
    }
}
