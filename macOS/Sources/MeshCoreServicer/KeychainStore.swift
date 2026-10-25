import Foundation
import Security

enum KeychainStore {
    private static let service = "org.meshcoreservicer.app.admin"
    static func load(_ key: String) throws -> String? {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:key, kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let d = result as? Data else { throw MeshErrorKeychain(status:status) }
        return String(data:d, encoding:.utf8)
    }
    static func save(_ password: String, key: String) throws {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:key]
        let attributes: [String:Any] = [kSecValueData as String:Data(password.utf8)]
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            var item = query.merging(attributes) { _,new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else { throw MeshErrorKeychain(status:status) }
        } else if result != errSecSuccess { throw MeshErrorKeychain(status:result) }
    }
    static func delete(_ key: String) throws {
        let result = SecItemDelete([kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:key] as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw MeshErrorKeychain(status:result) }
    }
}
private struct MeshErrorKeychain: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "Klíčenka macOS operaci odmítla (\(status))." }
}
