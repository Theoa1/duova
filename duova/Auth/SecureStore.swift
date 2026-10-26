import CryptoKit
import Foundation
import Security

enum SecureStoreError: Error {
    case keychain(OSStatus)
    case corrupt
    case writeFailed
}

/// Encrypted, device-bound storage for everything Duova keeps about an account.
///
/// - Every value is sealed with **AES-256-GCM** (CryptoKit). GCM is
///   authenticated, so tampering or swapping files is detected on open.
/// - The 256-bit master key is generated on first use and lives only in the
///   iOS **Keychain** (`WhenUnlockedThisDeviceOnly`): it is never written to a
///   file, never synced, and never leaves the device.
/// - Two independent subkeys are derived from it with HKDF: one encrypts data,
///   the other produces keyed lookup tags (so e-mail addresses never appear in
///   plaintext, not even as Keychain item names).
/// - Each sealed file is bound to its own name as authenticated data, and is
///   written with iOS Data Protection `complete` and excluded from backups.
final class SecureStore {
    static let shared = SecureStore()

    private struct Keys {
        let data: SymmetricKey
        let lookup: SymmetricKey
    }

    private static let formatVersion: UInt8 = 1
    private let directory: URL
    private let keyService: String
    private let keyAccount = "master-key.v1"
    private var cachedKeys: Keys?

    init(directory: URL? = nil, keyService: String = "com.duova.securestore") {
        let base = directory ?? URL.applicationSupportDirectory.appending(path: "Duova/Secure", directoryHint: .isDirectory)
        self.directory = base
        self.keyService = keyService
    }

    // MARK: Sealing

    /// Encrypts `plaintext`, binding it to `context` (for example the file name).
    func seal(_ plaintext: Data, context: String) throws -> Data {
        let keys = try loadKeys()
        let box = try AES.GCM.seal(plaintext, using: keys.data, authenticating: Data(context.utf8))
        guard let combined = box.combined else { throw SecureStoreError.corrupt }
        return Data([Self.formatVersion]) + combined
    }

    /// Decrypts a blob produced by `seal`. Throws if it was altered or sealed for another context.
    func open(_ blob: Data, context: String) throws -> Data {
        guard blob.first == Self.formatVersion else { throw SecureStoreError.corrupt }
        let keys = try loadKeys()
        let box = try AES.GCM.SealedBox(combined: blob.dropFirst())
        return try AES.GCM.open(box, using: keys.data, authenticating: Data(context.utf8))
    }

    /// A keyed, one-way tag for `value` (HMAC-SHA256, hex). Stable on this device only.
    func lookupTag(for value: String) throws -> String {
        let keys = try loadKeys()
        let code = HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: keys.lookup)
        return code.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Encrypted files

    func saveData(_ data: Data, name: String) throws {
        let sealed = try seal(data, context: name)
        try ensureDirectory()
        do {
            try sealed.write(to: fileURL(name), options: [.atomic, .completeFileProtection])
        } catch {
            throw SecureStoreError.writeFailed
        }
    }

    /// The decrypted contents of `name`, or `nil` if it doesn't exist or can't be authenticated.
    func loadData(name: String) -> Data? {
        guard let blob = try? Data(contentsOf: fileURL(name)) else { return nil }
        return try? open(blob, context: name)
    }

    func save<T: Encodable>(_ value: T, name: String) throws {
        try saveData(JSONEncoder().encode(value), name: name)
    }

    func load<T: Decodable>(_ type: T.Type, name: String) -> T? {
        guard let data = loadData(name: name) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func remove(name: String) {
        try? FileManager.default.removeItem(at: fileURL(name))
    }

    /// Removes every sealed file whose name contains `fragment` (used to erase one account's data).
    func removeAll(containing fragment: String) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.contains(fragment) {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }

    // MARK: Files

    private func fileURL(_ name: String) -> URL {
        directory.appending(path: name + ".sealed", directoryHint: .notDirectory)
    }

    private func ensureDirectory() throws {
        var url = directory
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
    }

    // MARK: Keys

    private func loadKeys() throws -> Keys {
        if let cachedKeys { return cachedKeys }
        let master = try masterKey()
        let salt = Data("com.duova.securestore.hkdf".utf8)
        let keys = Keys(
            data: HKDF<SHA256>.deriveKey(
                inputKeyMaterial: master, salt: salt, info: Data("data.v1".utf8), outputByteCount: 32),
            lookup: HKDF<SHA256>.deriveKey(
                inputKeyMaterial: master, salt: salt, info: Data("lookup.v1".utf8), outputByteCount: 32)
        )
        cachedKeys = keys
        return keys
    }

    private func masterKey() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: keyAccount,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound || status == errSecSuccess else {
            throw SecureStoreError.keychain(status)
        }

        // First use (or an unreadable key): create a fresh one.
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: keyAccount,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
            kSecValueData as String: keyData
        ]
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: keyAccount,
            kSecUseDataProtectionKeychain as String: true
        ] as CFDictionary)
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw SecureStoreError.keychain(addStatus) }
        return key
    }
}
