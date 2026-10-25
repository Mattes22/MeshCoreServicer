import Foundation
import MeshCoreKit

actor ChatArchive {
    private let folder: URL
    private var revisions: [String:UInt64] = [:]
    private struct Snapshot: Codable { let version: Int; let account: String; let records: [ChatRecord] }
    init(folder: URL) { self.folder = folder }
    static func applicationArchive() -> ChatArchive {
        let root = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
        return ChatArchive(folder:root.appendingPathComponent("MeshCoreServicer/Messages",isDirectory:true))
    }
    private func file(_ account: String) throws -> URL {
        guard account.count == 64, account.allSatisfy({ $0.isHexDigit }) else { throw MeshError.invalid("identita companionu pro historii") }
        return folder.appendingPathComponent(account.lowercased()+".json")
    }
    func load(account: String) throws -> [ChatRecord] {
        let url = try file(account)
        guard FileManager.default.fileExists(atPath:url.path) else { return [] }
        let snapshot = try JSONDecoder().decode(Snapshot.self,from:Data(contentsOf:url))
        guard snapshot.version == 1, snapshot.account == account else { throw MeshError.invalid("verze nebo identita historie") }
        return Array(snapshot.records.suffix(5000))
    }
    func save(_ records: [ChatRecord], account: String, revision: UInt64) throws {
        guard revision >= (revisions[account] ?? 0) else { return }
        let url = try file(account)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let data = try JSONEncoder().encode(Snapshot(version:1,account:account,records:Array(records.suffix(5000))))
        try data.write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
        revisions[account] = revision
    }
}
