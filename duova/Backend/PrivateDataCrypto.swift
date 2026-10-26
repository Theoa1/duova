import CryptoKit
import Foundation
import Security

/// Where an encrypted value lives. It is authenticated with the ciphertext, so a
/// stored envelope can't be copied to another user, table, row or column and
/// still decrypt: the swap fails authentication instead of showing wrong data.
nonisolated struct EnvelopeContext: Hashable, Sendable {
    var userID: UUID
    var table: String
    var recordID: String
    var column: String

    /// The authenticated, unencrypted header that is bound to the ciphertext.
    var associatedData: Data { associatedData(version: "dv1") }

    func associatedData(version: String) -> Data {
        Data("duova|\(version)|\(userID.uuidString.lowercased())|\(table)|\(recordID)|\(column)".utf8)
    }
}

nonisolated enum PrivateDataError: Error, Equatable, LocalizedError {
    case malformedEnvelope
    case unsupportedVersion(String)
    /// Wrong key, altered ciphertext, or an envelope moved to a different row.
    case authenticationFailed
    case keyUnavailable(OSStatus)

    var errorDescription: String? {
        switch self {
        case .malformedEnvelope: "The stored data isn't in a recognized format."
        case .unsupportedVersion(let tag): "This data was written by a newer version (\(tag))."
        case .authenticationFailed: "The stored data couldn't be verified or decrypted."
        case .keyUnavailable: "The encryption key for this account isn't available on this device."
        }
    }
}

/// Versioned envelope for private Duova data: `dv1:<base64url(nonce | ciphertext | tag)>`.
///
/// - AES-256-GCM, with a fresh random 96-bit nonce for every encryption.
/// - The per-table encryption key is derived (HKDF-SHA256) from the account's
///   master key, so one table's key is never used for another's.
/// - The row's identity is bound in as associated data (see `EnvelopeContext`).
///
/// Everything here runs on the device. The server only ever receives the envelope.
nonisolated enum PrivateDataCrypto {
    static let tag = "dv1"

    static func seal(_ plaintext: Data, using masterKey: SymmetricKey, context: EnvelopeContext) throws -> String {
        let key = subkey(from: masterKey, context: context)
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: context.associatedData)
        // `combined` is nonce (12) + ciphertext + tag (16); it's non-nil for the default nonce size.
        guard let combined = box.combined else { throw PrivateDataError.malformedEnvelope }
        return "\(tag):" + base64URL(combined)
    }

    static func open(_ envelope: String, using masterKey: SymmetricKey, context: EnvelopeContext) throws -> Data {
        guard let separator = envelope.firstIndex(of: ":") else { throw PrivateDataError.malformedEnvelope }
        let version = String(envelope[..<separator])
        guard version == tag else { throw PrivateDataError.unsupportedVersion(version) }
        guard let combined = decodeBase64URL(String(envelope[envelope.index(after: separator)...])) else {
            throw PrivateDataError.malformedEnvelope
        }
        let box: AES.GCM.SealedBox
        do {
            box = try AES.GCM.SealedBox(combined: combined)
        } catch {
            throw PrivateDataError.malformedEnvelope
        }
        do {
            return try AES.GCM.open(box, using: subkey(from: masterKey, context: context), authenticating: context.associatedData)
        } catch {
            throw PrivateDataError.authenticationFailed
        }
    }

    // MARK: Double encryption (dv2)

    static let doubleTag = "dv2"

    /// Two independent layers, each with its own key, algorithm and nonce:
    ///
    /// 1. Inner: ChaCha20-Poly1305 under a subkey of the account's *vault key*.
    /// 2. Outer: AES-256-GCM under a subkey of the account's *master key*.
    ///
    /// Both layers bind the row's identity, and the keys are separate Keychain
    /// items, so breaking one algorithm or leaking one key still reveals nothing.
    /// Format: `dv2:<base64url(outer nonce | outer ciphertext | outer tag)>`.
    static func sealDouble(
        _ plaintext: Data, outer masterKey: SymmetricKey, inner vaultKey: SymmetricKey, context: EnvelopeContext
    ) throws -> String {
        let innerBox = try ChaChaPoly.seal(
            plaintext, using: subkey(from: vaultKey, context: context, label: "duova.dv2.inner"),
            authenticating: context.associatedData(version: "dv2-inner"))
        let outerBox = try AES.GCM.seal(
            innerBox.combined, using: subkey(from: masterKey, context: context, label: "duova.dv2.outer"),
            authenticating: context.associatedData(version: "dv2-outer"))
        guard let combined = outerBox.combined else { throw PrivateDataError.malformedEnvelope }
        return "\(doubleTag):" + base64URL(combined)
    }

    static func openDouble(
        _ envelope: String, outer masterKey: SymmetricKey, inner vaultKey: SymmetricKey, context: EnvelopeContext
    ) throws -> Data {
        guard let separator = envelope.firstIndex(of: ":") else { throw PrivateDataError.malformedEnvelope }
        let version = String(envelope[..<separator])
        guard version == doubleTag else { throw PrivateDataError.unsupportedVersion(version) }
        guard let combined = decodeBase64URL(String(envelope[envelope.index(after: separator)...])),
              let outerBox = try? AES.GCM.SealedBox(combined: combined)
        else { throw PrivateDataError.malformedEnvelope }
        do {
            let innerCombined = try AES.GCM.open(
                outerBox, using: subkey(from: masterKey, context: context, label: "duova.dv2.outer"),
                authenticating: context.associatedData(version: "dv2-outer"))
            let innerBox = try ChaChaPoly.SealedBox(combined: innerCombined)
            return try ChaChaPoly.open(
                innerBox, using: subkey(from: vaultKey, context: context, label: "duova.dv2.inner"),
                authenticating: context.associatedData(version: "dv2-inner"))
        } catch {
            throw PrivateDataError.authenticationFailed
        }
    }

    static func sealDouble<Value: Encodable>(
        _ value: Value, outer: SymmetricKey, inner: SymmetricKey, context: EnvelopeContext
    ) throws -> String {
        try sealDouble(JSONEncoder().encode(value), outer: outer, inner: inner, context: context)
    }

    static func openDouble<Value: Decodable>(
        _ type: Value.Type, from envelope: String, outer: SymmetricKey, inner: SymmetricKey, context: EnvelopeContext
    ) throws -> Value {
        try JSONDecoder().decode(type, from: openDouble(envelope, outer: outer, inner: inner, context: context))
    }

    /// An opaque, per-account reference for an app (HMAC-SHA256 of its slug), so
    /// the server can key rows by app without learning which apps someone uses.
    static func appReference(for slug: String, masterKey: SymmetricKey, userID: UUID) -> String {
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey, salt: Data(userID.uuidString.lowercased().utf8),
            info: Data("duova.app-reference".utf8), outputByteCount: 32)
        return base64URL(Data(HMAC<SHA256>.authenticationCode(for: Data(slug.utf8), using: key)))
    }

    static func seal<Value: Encodable>(_ value: Value, using masterKey: SymmetricKey, context: EnvelopeContext) throws -> String {
        try seal(JSONEncoder().encode(value), using: masterKey, context: context)
    }

    static func open<Value: Decodable>(
        _ type: Value.Type, from envelope: String, using masterKey: SymmetricKey, context: EnvelopeContext
    ) throws -> Value {
        try JSONDecoder().decode(type, from: open(envelope, using: masterKey, context: context))
    }

    // MARK: Keys

    private static func subkey(
        from masterKey: SymmetricKey, context: EnvelopeContext, label: String = "duova.dv1"
    ) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            salt: Data(context.userID.uuidString.lowercased().utf8),
            info: Data("\(label).\(context.table)".utf8),
            outputByteCount: 32
        )
    }

    static func makeMasterKey() -> SymmetricKey { SymmetricKey(size: .bits256) }

    // MARK: Encoding

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decodeBase64URL(_ text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}

/// Supplies each account's master key.
nonisolated protocol PrivateKeyProviding: Sendable {
    func masterKey(for userID: UUID) throws -> SymmetricKey
    func removeKey(for userID: UUID)
}

/// Keeps one random 256-bit key per account in the iOS Keychain.
///
/// The key never syncs through iCloud Keychain (`ThisDeviceOnly`) and is never
/// uploaded in the clear. Reading never creates a key: only `DeviceKeyring`
/// decides whether this device makes the account's first keys or receives
/// them, sealed to this device, from a device that already has them. That
/// keeps a new device from quietly starting a second, incompatible key.
nonisolated struct KeychainKeyProvider: PrivateKeyProviding {
    private let service: String

    init(service: String = "app.duova.private-data-key") {
        self.service = service
    }

    /// The second, independent key used for the inner layer of `dv2` envelopes.
    static let vault = KeychainKeyProvider(service: "app.duova.vault-key")

    func masterKey(for userID: UUID) throws -> SymmetricKey {
        guard let existing = try read(account: userID.uuidString.lowercased()) else {
            throw PrivateDataError.keyUnavailable(errSecItemNotFound)
        }
        return SymmetricKey(data: existing)
    }

    func hasKey(for userID: UUID) -> Bool {
        (try? read(account: userID.uuidString.lowercased())) != nil
    }

    /// Makes the account's key on this device, or returns the one already here.
    @discardableResult
    func createKey(for userID: UUID) throws -> SymmetricKey {
        if let existing = try read(account: userID.uuidString.lowercased()) { return SymmetricKey(data: existing) }
        let fresh = PrivateDataCrypto.makeMasterKey()
        try install(fresh, for: userID)
        return fresh
    }

    /// Stores a key (for example one received from another device), replacing any key here.
    func install(_ key: SymmetricKey, for userID: UUID) throws {
        let account = userID.uuidString.lowercased()
        removeKey(for: userID)
        let status = SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable: false,
            kSecValueData: key.withUnsafeBytes { Data($0) },
        ] as CFDictionary, nil)
        guard status == errSecSuccess else { throw PrivateDataError.keyUnavailable(status) }
    }

    func removeKey(for userID: UUID) {
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: userID.uuidString.lowercased(),
        ] as CFDictionary)
    }

    private func read(account: String) throws -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw PrivateDataError.keyUnavailable(status)
        }
    }
}
