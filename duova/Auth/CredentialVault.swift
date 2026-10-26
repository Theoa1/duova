import Foundation
import Security

/// What Duova keeps to verify a password. There is no password here, only a
/// salted one-way hash.
struct CredentialRecord: Codable, Equatable {
    var accountID: UUID
    var salt: Data
    var hash: Data
    var iterations: Int
}

/// Stores credential records in the iOS Keychain. Each record is
/// AES-256-GCM sealed by `SecureStore` before it is handed to the Keychain, and
/// is filed under an HMAC tag of the e-mail address, so neither the address nor
/// the hash is readable in plaintext, even to a process that can list Keychain
/// item names.
final class CredentialVault {
    private let store: SecureStore
    private let service = "com.duova.credentials"

    init(store: SecureStore = .shared) {
        self.store = store
    }

    func record(forEmail email: String) -> CredentialRecord? {
        guard let tag = try? store.lookupTag(for: email) else { return nil }
        var query = baseQuery(tag: tag)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let blob = item as? Data,
              let plain = try? store.open(blob, context: "credential"),
              let record = try? JSONDecoder().decode(CredentialRecord.self, from: plain)
        else { return nil }
        return record
    }

    func save(_ record: CredentialRecord, forEmail email: String) throws {
        let tag = try store.lookupTag(for: email)
        let sealed = try store.seal(try JSONEncoder().encode(record), context: "credential")
        SecItemDelete(baseQuery(tag: tag) as CFDictionary)
        var attributes = baseQuery(tag: tag)
        attributes[kSecValueData as String] = sealed
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        attributes[kSecAttrSynchronizable as String] = false
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecureStoreError.keychain(status) }
    }

    func remove(forEmail email: String) {
        guard let tag = try? store.lookupTag(for: email) else { return }
        SecItemDelete(baseQuery(tag: tag) as CFDictionary)
    }

    private func baseQuery(tag: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
            kSecUseDataProtectionKeychain as String: true
        ]
    }
}
