import Foundation
import Combine
import MeshCoreKit

struct NodeOperations: Codable, Equatable, Sendable {
    var samples: [HealthSample] = []
    var snapshots: [ConfigSnapshot] = []
    var restart: RestartReview?
    var unverified: [UnverifiedChange] = []
}
struct OperationsDocument: Codable, Sendable {
    var version = 1
    let account: String
    var nodes: [String:NodeOperations] = [:]
    func validate() throws {
        _ = try RepeaterCommand.publicKey(account)
        guard version == 1, nodes.count <= 32 else { throw MeshError.invalid("historie správy") }
        for (key,node) in nodes {
            _ = try RepeaterCommand.publicKey(key)
            guard node.samples.count <= 2000, node.snapshots.count <= 30, node.unverified.count <= 50 else { throw MeshError.invalid("limity historie správy") }
            for snapshot in node.snapshots { try snapshot.validate(); guard snapshot.account == account && snapshot.repeater == key else { throw MeshError.invalid("identita snímku") } }
            for change in node.unverified {
                if let expected = change.expected { _ = try CLIValidation.validate(key:change.key,value:expected) }
            }
        }
    }
}
actor OperationsArchive {
    private let folder: URL
    private var revisions: [String:UInt64] = [:]
    init(folder: URL) { self.folder = folder }
    static func applicationArchive() -> Self { Self(folder:FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("MeshCoreServicer/Operations",isDirectory:true)) }
    func load(account: String) throws -> OperationsDocument {
        _ = try RepeaterCommand.publicKey(account)
        let url = folder.appendingPathComponent(account+".json")
        guard FileManager.default.fileExists(atPath:url.path) else { return OperationsDocument(account:account) }
        let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size <= 32_000_000 else { throw MeshError.invalid("velikost historie") }
        let doc = try JSONDecoder().decode(OperationsDocument.self,from:Data(contentsOf:url))
        try doc.validate(); guard doc.account == account else { throw MeshError.invalid("identita historie") }; return doc
    }
    func save(_ doc: OperationsDocument, revision: UInt64) throws {
        try doc.validate(); guard revision >= (revisions[doc.account] ?? 0) else { return }
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let url = folder.appendingPathComponent(doc.account+".json")
        try JSONEncoder().encode(doc).write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path); revisions[doc.account] = revision
    }
}
@MainActor final class OperationsModel: ObservableObject {
    @Published private(set) var document: OperationsDocument?
    @Published private(set) var selectedID: String?
    @Published private(set) var storageError: String?
    private let archive: OperationsArchive?
    private var writable = true
    private var revision: UInt64 = 0
    private var task: Task<Void,Never>?
    init(archive: OperationsArchive? = nil) { self.archive = archive }
    var current: NodeOperations { selectedID.flatMap { document?.nodes[$0] } ?? NodeOperations() }
    func select(_ id: String?) { selectedID = id }
    func activate(account: String) async {
        guard document?.account != account else { return }
        await flush(); document = nil; writable = true; storageError = nil
        do { document = try await archive?.load(account:account) ?? OperationsDocument(account:account) }
        catch { document = OperationsDocument(account:account); writable = false; storageError = "Historii správy nelze načíst. Původní soubor nebude přepsán." }
    }
    @discardableResult private func update(_ id: String,_ edit: (inout NodeOperations)->Void) -> Bool {
        guard document != nil else { return false }
        guard document!.nodes[id] != nil || document!.nodes.count < 32 else { storageError = "Historie obsahuje 32 uzlů. Nový uzel nelze přidat; původní data zůstala zachována."; return false }
        var node = document!.nodes[id] ?? NodeOperations(); edit(&node); document!.nodes[id] = node; persist(); return true
    }
    func record(_ status: RepeaterStatus, repeater: String, date: Date = Date()) {
        update(repeater) { node in
            let sample = HealthSample(status:status,date:date)
            if let old = node.samples.last, sample.suggestsRestart(after:old) { node.restart = RestartReview(date:date,reason:"Pokles doby běhu mezi dvěma načtenými stavy · možný restart") }
            node.samples.append(sample); node.samples = Array(node.samples.suffix(2000)); if let review = node.restart, date >= review.date { node.restart?.reachable = date }
        }
    }
    func restartRequested(repeater: String) { update(repeater) { $0.restart = RestartReview(reason:"Odeslaný požadavek na restart · provedení zatím nepotvrzené") } }
    func clockChecked(repeater: String, text: String, now: Date = Date()) {
        guard let date = RepeaterCommand.clockDate(text.trimmingCharacters(in:.whitespacesAndNewlines)), abs(date.timeIntervalSince(now)) <= 120 else { return }
        update(repeater) { node in if let review = node.restart, now >= review.date { node.restart?.clockChecked = now } }
    }
    func beginChange(_ key: String,repeater: String,expected: String? = nil) {
        let allowed = CLIValidation.keys.contains(key) ? expected.flatMap{try? CLIValidation.validate(key:key,value:$0)} : nil
        update(repeater) { node in node.unverified.removeAll{$0.key == key}; node.unverified.append(UnverifiedChange(key:key,expected:allowed)); node.unverified = Array(node.unverified.suffix(50)) }
    }
    func verifiedChange(_ key: String,repeater: String) { update(repeater) { $0.unverified.removeAll{$0.key == key} } }
    func addSnapshot(_ snapshot: ConfigSnapshot) throws {
        try snapshot.validate(); guard document?.account == snapshot.account else { throw MeshError.invalid("snímek patří jinému companionu") }
        guard update(snapshot.repeater,{ node in node.snapshots.removeAll{$0.id == snapshot.id}; node.snapshots.append(snapshot); node.snapshots = Array(node.snapshots.suffix(30)) }) else { throw MeshError.remote(storageError ?? "Historie snímku není dostupná.") }
    }
    func removeSnapshot(_ id: UUID) { guard let key = selectedID else { return }; update(key) { $0.snapshots.removeAll{$0.id == id} } }
    func flush() async { await task?.value }
    private func persist() {
        guard writable, let archive, let document else { return }; revision += 1; let revision = revision
        task = Task { [weak self] in
            do { try await archive.save(document,revision:revision) }
            catch { self?.storageError = "Historii správy nelze uložit na disk." }
        }
    }
}
