import Foundation
import MeshCoreKit

extension AppModel {
    func requestMessageSync(manual: Bool = false) {
        if manual { messages.syncError = nil }
        guard messages.syncError == nil else { return }
        syncRequested = true
        guard initialized, messages.account != nil, messageSyncTask == nil else { return }
        let generation = connectionGeneration
        messageSyncTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.messageSyncTask = nil
                if self.syncRequested && self.initialized && self.messages.syncError == nil { self.requestMessageSync() }
            }
            while self.syncRequested && self.initialized && self.connectionGeneration == generation && !Task.isCancelled {
                if self.busy { do { try await Task.sleep(nanoseconds:100_000_000) } catch { break }; continue }
                self.syncRequested = false; self.busy = true; self.progress = "Přijímám zprávy z companionu…"
                do {
                    try await self.session.syncMessages()
                    if self.connectionGeneration == generation { self.progress = "Zprávy synchronizovány"; self.liveNotifications = true }
                } catch {
                    if self.connectionGeneration == generation {
                        self.messages.syncError = error.localizedDescription
                        self.log("Příjem zpráv nebyl dokončen.",level:.warning)
                    }
                    self.syncRequested = false
                }
                self.busy = false
            }
        }
    }
    func refreshChannels() {
        guard initialized, !busy, let count = deviceInfo?.maxChannels else { return }
        perform("Načítám kanály companionu…") {
            try await self.session.channels(count:count)
            self.messages.finishChannelRefresh(indices:Set(0..<count))
            self.requestMessageSync()
        }
    }
    func sendChat() {
        guard initialized, !busy, let id = messages.selectedConversation, let account = messages.account else { return }
        let text = messages.drafts[id] ?? ""
        let channel = messages.channels.values.first { $0.id == id && $0.configured }
        let prefix = id.hasPrefix("dm:") ? String(id.dropFirst(3)) : ""
        let matches = contacts.filter { $0.key.prefix(6).hex == prefix }
        let peer = matches.count == 1 && matches[0].kind == 1 && matches[0].stored ? matches[0] : nil
        guard channel != nil || peer != nil else { error = "Vyberte aktuální kanál nebo jednoznačný uložený companion kontakt. Repeaterům se textový chat neposílá."; return }
        do {
            try MeshMessaging.validate(text,limit:channel == nil ? MeshMessaging.maximumTextBytes : MeshMessaging.channelLimit(sender:selfInfo?.name ?? ""))
            let timestamp = messages.nextTimestamp()
            var record = ChatRecord(conversationID:id,title:channel?.displayName ?? peer!.name,channelIndex:channel?.index,peerPrefix:peer?.key.prefix(6).hex,outgoing:true,sender:selfInfo?.name ?? "Já",text:text,timestamp:timestamp,delivery:.sending)
            if let channel {
                guard let sender = selfInfo?.name else { throw MeshError.invalid("nenačtený název companionu") }
                record.packetFingerprint = try channel.packetFingerprint(timestamp:timestamp,wireText:sender+": "+text)
                record.capturedForwardings = 0
            }
            let messageID = record.id
            messages.appendOutgoing(record); messages.drafts[id] = ""
            perform("Předávám zprávu companionu…") {
                do {
                    if let channel {
                        try await self.session.sendChannel(index:channel.index,text:text,sender:self.selfInfo?.name ?? "",timestamp:timestamp)
                        guard self.messages.account == account else { return }
                        self.messages.accepted(id:messageID,receipt:nil)
                    } else if let peer {
                        let receipt = try await self.session.sendDirect(key:peer.key,text:text,timestamp:timestamp)
                        guard self.messages.account == account else { return }
                        self.messages.accepted(id:messageID,receipt:receipt)
                    }
                    self.log("Companion přijal požadavek na odeslání zprávy; obsah se neloguje.")
                } catch {
                    guard self.messages.account == account else { return }
                    let rejected: Bool
                    if case MeshError.remote = error { rejected = true } else { rejected = false }
                    self.messages.sendFailed(id:messageID,rejected:rejected)
                    throw error
                }
            }
        } catch { self.error = error.localizedDescription }
    }
}
