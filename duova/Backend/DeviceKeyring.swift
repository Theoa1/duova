import CommonCrypto
import CryptoKit
import Foundation
import Observation
import Security
import Supabase
import Synchronization
import UIKit

// MARK: - Device identity

/// This device's identity for one account: a random id and an X25519 key pair.
/// Other devices seal the account's keys to the public half; the private half
/// never leaves this device's Keychain (`ThisDeviceOnly`).
nonisolated struct DeviceIdentity: Sendable {
    let deviceID: UUID
    let privateKey: Curve25519.KeyAgreement.PrivateKey

    var publicKeyText: String { PrivateDataCrypto.base64URL(privateKey.publicKey.rawRepresentation) }
    var safetyCode: String { DeviceKeyEnvelope.safetyCode(deviceID: deviceID, publicKey: publicKeyText) }

    private static let service = "app.duova.device-identity"

    private struct Stored: Codable {
        var deviceID: UUID
        var key: Data
    }

    /// Loads this device's identity for the account, creating it the first time.
    static func load(for userID: UUID) throws -> DeviceIdentity {
        let account = userID.uuidString.lowercased()
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data,
           let stored = try? JSONDecoder().decode(Stored.self, from: data),
           let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: stored.key) {
            return DeviceIdentity(deviceID: stored.deviceID, privateKey: key)
        }
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PrivateDataError.keyUnavailable(status)
        }

        let identity = DeviceIdentity(deviceID: UUID(), privateKey: Curve25519.KeyAgreement.PrivateKey())
        let data = try JSONEncoder().encode(Stored(deviceID: identity.deviceID, key: identity.privateKey.rawRepresentation))
        remove(for: userID)
        let added = SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable: false,
            kSecValueData: data,
        ] as CFDictionary, nil)
        guard added == errSecSuccess else { throw PrivateDataError.keyUnavailable(added) }
        return identity
    }

    static func remove(for userID: UUID) {
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: userID.uuidString.lowercased(),
        ] as CFDictionary)
    }
}

// MARK: - Key envelopes

/// Seals the account's two keys to one device:
///
/// `dk1:<base64url(encapsulated key | ciphertext)>`, made with HPKE
/// (RFC 9180: X25519, HKDF-SHA256, ChaCha20-Poly1305). The account, device and
/// key version are bound in as both HPKE info and associated data, so an
/// envelope can't be replayed to another account, device or version. Only the
/// device holding the matching private key can open it; the server can't.
nonisolated enum DeviceKeyEnvelope {
    static let tag = "dk1"
    static let algorithm = "hpke_x25519_sha256_chachapoly_v1"
    private static let suite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly

    private static func binding(user: UUID, device: UUID, version: Int) -> Data {
        Data("duova|device-keys|v1|\(user.uuidString.lowercased())|\(device.uuidString.lowercased())|\(version)".utf8)
    }

    static func seal(
        master: SymmetricKey, vault: SymmetricKey, toPublicKey publicKeyText: String,
        user: UUID, device: UUID, version: Int
    ) throws -> String {
        guard let raw = PrivateDataCrypto.decodeBase64URL(publicKeyText),
              let recipient = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw)
        else { throw PrivateDataError.malformedEnvelope }
        let info = binding(user: user, device: device, version: version)
        var sender = try HPKE.Sender(recipientKey: recipient, ciphersuite: suite, info: info)
        var plaintext = master.withUnsafeBytes { Data($0) }
        plaintext.append(vault.withUnsafeBytes { Data($0) })
        let ciphertext = try sender.seal(plaintext, authenticating: info)
        return "\(tag):" + PrivateDataCrypto.base64URL(sender.encapsulatedKey + ciphertext)
    }

    static func open(
        _ envelope: String, with identity: DeviceIdentity, user: UUID, version: Int
    ) throws -> (master: SymmetricKey, vault: SymmetricKey) {
        let prefix = "\(tag):"
        guard envelope.hasPrefix(prefix),
              let combined = PrivateDataCrypto.decodeBase64URL(String(envelope.dropFirst(prefix.count))),
              combined.count > 32
        else { throw PrivateDataError.malformedEnvelope }
        let info = binding(user: user, device: identity.deviceID, version: version)
        do {
            var recipient = try HPKE.Recipient(
                privateKey: identity.privateKey, ciphersuite: suite, info: info,
                encapsulatedKey: combined.prefix(32))
            let plaintext = try recipient.open(combined.dropFirst(32), authenticating: info)
            guard plaintext.count == 64 else { throw PrivateDataError.malformedEnvelope }
            return (SymmetricKey(data: plaintext.prefix(32)), SymmetricKey(data: plaintext.suffix(32)))
        } catch {
            throw PrivateDataError.authenticationFailed
        }
    }

    /// A one-way check value for the account's keys (HMAC under the keys
    /// themselves), so a device can tell whether its keys are the account's
    /// without anyone learning anything about the keys.
    static func fingerprint(master: SymmetricKey, vault: SymmetricKey, user: UUID) -> String {
        var material = master.withUnsafeBytes { Data($0) }
        material.append(vault.withUnsafeBytes { Data($0) })
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data("duova|key-check|v1|\(user.uuidString.lowercased())".utf8),
            using: SymmetricKey(data: material))
        return PrivateDataCrypto.base64URL(Data(mac))
    }

    /// Twelve digits both screens show, so the person can confirm they're
    /// approving their own device and not a key the server slipped in.
    ///
    /// The server knows the real key, so a short code could be matched by
    /// trying keys until one gives the same digits. Twelve digits behind a
    /// deliberately slow PBKDF2 (200,000 rounds) put that out of reach in
    /// the minute or so a person spends comparing codes.
    static func safetyCode(deviceID: UUID, publicKey: String) -> String {
        let input = "duova|device-code|v2|\(deviceID.uuidString.lowercased())|\(publicKey)"
        if let cached = codeCache.withLock({ $0[input] }) { return cached }

        let password = Array(input.utf8)
        let salt = Array("duova-device-code-v2".utf8)
        var derived = [UInt8](repeating: 0, count: 8)
        let status = password.withUnsafeBufferPointer { passwordBytes in
            passwordBytes.withMemoryRebound(to: CChar.self) { passwordChars in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2), passwordChars.baseAddress, passwordChars.count,
                    salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 200_000,
                    &derived, derived.count)
            }
        }
        guard status == kCCSuccess else { return "—" }
        let number = derived.reduce(UInt64(0)) { $0 << 8 | UInt64($1) } % 1_000_000_000_000
        let digits = String(format: "%012llu", number)
        let code = stride(from: 0, to: 12, by: 4).map { start in
            let from = digits.index(digits.startIndex, offsetBy: start)
            return String(digits[from..<digits.index(from, offsetBy: 4)])
        }.joined(separator: " ")
        codeCache.withLock { $0[input] = code }
        return code
    }

    private static let codeCache = Mutex<[String: String]>([:])
}

// MARK: - Keyring

/// One device signed in to the account.
struct LinkedDevice: Identifiable, Equatable {
    let id: UUID
    var label: String
    let safetyCode: String
    let addedAt: Date?
    let isThisDevice: Bool
    let hasAccess: Bool
}

/// Decides how this device gets the account's encryption keys, and lets a
/// device that has them approve new ones.
///
/// - The first device makes the keys and seals a copy to itself.
/// - A new device registers its public key and waits. It never makes keys of
///   its own, so it can't start a second, incompatible set.
/// - A device with the keys approves it (after Face ID / Touch ID / passcode
///   and checking the twelve-digit code), sealing both keys to the new device.
/// - If every device with the keys is gone, "Start over" erases the encrypted
///   data nobody can open any more and makes new keys.
@MainActor
@Observable
final class DeviceKeyring {
    enum State: Equatable {
        /// Signed out, or not checked yet.
        case idle
        case checking
        /// This device has the account's keys.
        case ready
        /// Waiting for another device to approve this one.
        case waitingForApproval(code: String)
        /// Couldn't reach the server and this device has no keys yet.
        case offline
    }

    private(set) var state: State = .idle
    private(set) var devices: [LinkedDevice] = []
    /// Set once this device has the keys; private sync waits for it.
    private(set) var readyAccountID: UUID?

    private var accountID: UUID?
    private var keyVersion = 1
    private let master = KeychainKeyProvider()
    private let vault = KeychainKeyProvider.vault

    var pendingDevices: [LinkedDevice] { devices.filter { !$0.hasAccess && !$0.isThisDevice } }

    private static let devicesTable = "duova_user_devices"
    private static let envelopesTable = "duova_user_key_envelopes"

    private struct DeviceRow: Codable {
        let userID: UUID
        let deviceID: UUID
        var publicWrappingKey: String?
        var encryptedLabel: String?
        var createdAt: Date?
        enum CodingKeys: String, CodingKey {
            case userID = "user_id", deviceID = "device_id", publicWrappingKey = "public_wrapping_key"
            case encryptedLabel = "encrypted_label", createdAt = "created_at"
        }
    }

    private struct EnvelopeRow: Codable {
        let userID: UUID
        let deviceID: UUID
        let keyVersion: Int
        var wrappedKeyCiphertext: String
        var wrappingAlgorithm: String
        var keyFingerprint: String?
        enum CodingKeys: String, CodingKey {
            case userID = "user_id", deviceID = "device_id", keyVersion = "key_version"
            case wrappedKeyCiphertext = "wrapped_key_ciphertext", wrappingAlgorithm = "wrapping_algorithm"
            case keyFingerprint = "key_fingerprint"
        }
    }

    private struct LabelUpdate: Encodable {
        let encryptedLabel: String
        enum CodingKeys: String, CodingKey { case encryptedLabel = "encrypted_label" }
    }

    /// The cloud client, only while it's signed in as this account.
    private func client(for user: UUID) -> SupabaseClient? {
        guard let client = DuovaBackend.client, client.auth.currentUser?.id == user else { return nil }
        return client
    }

    private var hasLocalKeys: Bool {
        guard let accountID else { return false }
        return master.hasKey(for: accountID) && vault.hasKey(for: accountID)
    }

    // MARK: Setup

    /// Works out whether this device has, should make, or must request the keys.
    func prepare(accountID: UUID?) async {
        self.accountID = accountID
        readyAccountID = nil
        devices = []
        guard let accountID else { state = .idle; return }
        state = .checking

        guard let client = client(for: accountID) else {
            // Without Duova's servers everything stays on this device.
            if (try? master.createKey(for: accountID)) != nil, (try? vault.createKey(for: accountID)) != nil {
                markReady(accountID)
            } else {
                state = .offline
            }
            return
        }

        let envelopes: [EnvelopeRow]
        do {
            envelopes = try await client.from(Self.envelopesTable)
                .select("user_id,device_id,key_version,wrapped_key_ciphertext,wrapping_algorithm,key_fingerprint")
                .eq("user_id", value: accountID.uuidString.lowercased())
                .order("key_version", ascending: false)
                .execute().value
        } catch {
            // Offline: keys already here keep working; a new device waits.
            if hasLocalKeys { markReady(accountID) } else { state = .offline }
            return
        }
        guard self.accountID == accountID, let identity = try? DeviceIdentity.load(for: accountID) else {
            state = .offline
            return
        }

        guard let latest = envelopes.first else {
            await becomeFirstDevice(accountID, identity: identity, client: client, version: 1)
            return
        }
        keyVersion = latest.keyVersion
        let current = envelopes.filter { $0.keyVersion == latest.keyVersion }

        if hasLocalKeys, let localPrint = localFingerprint(), localPrint == latest.keyFingerprint {
            if !current.contains(where: { $0.deviceID == identity.deviceID }) {
                try? await register(identity, client: client)
                try? await sealKeys(to: identity.deviceID, publicKey: identity.publicKeyText, client: client)
            }
            markReady(accountID)
            await refreshDevices()
            return
        }

        if let mine = current.first(where: { $0.deviceID == identity.deviceID }),
           (try? install(mine, identity: identity, user: accountID)) == true {
            markReady(accountID)
            await refreshDevices()
            return
        }

        try? await register(identity, client: client)
        state = .waitingForApproval(code: identity.safetyCode)
    }

    private func markReady(_ accountID: UUID) {
        state = .ready
        readyAccountID = accountID
    }

    private func localFingerprint() -> String? {
        guard let accountID,
              let m = try? master.masterKey(for: accountID), let v = try? vault.masterKey(for: accountID)
        else { return nil }
        return DeviceKeyEnvelope.fingerprint(master: m, vault: v, user: accountID)
    }

    private func becomeFirstDevice(_ accountID: UUID, identity: DeviceIdentity, client: SupabaseClient, version: Int) async {
        do {
            try master.createKey(for: accountID)
            try vault.createKey(for: accountID)
            keyVersion = version
            try await register(identity, client: client)
            try await sealKeys(to: identity.deviceID, publicKey: identity.publicKeyText, client: client)
            markReady(accountID)
            await refreshDevices()
        } catch {
            // The keys work here even if the server copy failed; it's retried next launch.
            if hasLocalKeys { markReady(accountID) } else { state = .offline }
        }
    }

    private func register(_ identity: DeviceIdentity, client: SupabaseClient) async throws {
        guard let accountID else { return }
        let existing: [DeviceRow] = try await client.from(Self.devicesTable)
            .select("user_id,device_id")
            .eq("user_id", value: accountID.uuidString.lowercased())
            .eq("device_id", value: identity.deviceID.uuidString.lowercased())
            .execute().value
        guard existing.isEmpty else { return }
        try await client.from(Self.devicesTable)
            .insert(DeviceRow(userID: accountID, deviceID: identity.deviceID, publicWrappingKey: identity.publicKeyText))
            .execute()
    }

    private func sealKeys(to device: UUID, publicKey: String, client: SupabaseClient) async throws {
        guard let accountID else { return }
        let m = try master.masterKey(for: accountID)
        let v = try vault.masterKey(for: accountID)
        let envelope = try DeviceKeyEnvelope.seal(
            master: m, vault: v, toPublicKey: publicKey, user: accountID, device: device, version: keyVersion)
        try await client.from(Self.envelopesTable)
            .insert(EnvelopeRow(
                userID: accountID, deviceID: device, keyVersion: keyVersion,
                wrappedKeyCiphertext: envelope, wrappingAlgorithm: DeviceKeyEnvelope.algorithm,
                keyFingerprint: DeviceKeyEnvelope.fingerprint(master: m, vault: v, user: accountID)))
            .execute()
    }

    /// Opens keys sealed to this device and keeps them, only if they match the
    /// account's published check value.
    private func install(_ row: EnvelopeRow, identity: DeviceIdentity, user: UUID) throws -> Bool {
        let keys = try DeviceKeyEnvelope.open(row.wrappedKeyCiphertext, with: identity, user: user, version: row.keyVersion)
        guard DeviceKeyEnvelope.fingerprint(master: keys.master, vault: keys.vault, user: user) == row.keyFingerprint else {
            return false
        }
        try master.install(keys.master, for: user)
        try vault.install(keys.vault, for: user)
        return true
    }

    // MARK: Waiting for approval

    /// While waiting, checks every few seconds whether another device approved this one.
    func waitForApproval() async {
        while !Task.isCancelled, case .waitingForApproval = state {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, case .waitingForApproval = state, let accountID,
                  let client = client(for: accountID), let identity = try? DeviceIdentity.load(for: accountID)
            else { continue }
            let rows: [EnvelopeRow]? = try? await client.from(Self.envelopesTable)
                .select("user_id,device_id,key_version,wrapped_key_ciphertext,wrapping_algorithm,key_fingerprint")
                .eq("user_id", value: accountID.uuidString.lowercased())
                .eq("device_id", value: identity.deviceID.uuidString.lowercased())
                .order("key_version", ascending: false)
                .execute().value
            if let row = rows?.first, (try? install(row, identity: identity, user: accountID)) == true {
                keyVersion = row.keyVersion
                markReady(accountID)
                await refreshDevices()
            }
        }
    }

    // MARK: Devices

    func refreshDevices() async {
        guard let accountID, let client = client(for: accountID) else { return }
        do {
            let rows: [DeviceRow] = try await client.from(Self.devicesTable)
                .select("user_id,device_id,public_wrapping_key,encrypted_label,created_at")
                .eq("user_id", value: accountID.uuidString.lowercased())
                .order("created_at", ascending: true)
                .execute().value
            let envelopes: [EnvelopeRow] = try await client.from(Self.envelopesTable)
                .select("user_id,device_id,key_version,wrapped_key_ciphertext,wrapping_algorithm,key_fingerprint")
                .eq("user_id", value: accountID.uuidString.lowercased())
                .eq("key_version", value: keyVersion)
                .execute().value
            let withAccess = Set(envelopes.map(\.deviceID))
            let me = try? DeviceIdentity.load(for: accountID)
            devices = rows.map { row in
                LinkedDevice(
                    id: row.deviceID,
                    label: openLabel(row) ?? String(localized: "New device"),
                    safetyCode: DeviceKeyEnvelope.safetyCode(deviceID: row.deviceID, publicKey: row.publicWrappingKey ?? ""),
                    addedAt: row.createdAt,
                    isThisDevice: row.deviceID == me?.deviceID,
                    hasAccess: withAccess.contains(row.deviceID))
            }
            if state == .ready, let me, let mine = rows.first(where: { $0.deviceID == me.deviceID }), mine.encryptedLabel == nil {
                await saveLabel(for: me.deviceID, client: client)
            }
        } catch {
            // Keep the last list.
        }
    }

    private func labelContext(_ device: UUID) -> EnvelopeContext? {
        accountID.map {
            EnvelopeContext(userID: $0, table: Self.devicesTable, recordID: device.uuidString.lowercased(), column: "encrypted_label")
        }
    }

    private func openLabel(_ row: DeviceRow) -> String? {
        guard let envelope = row.encryptedLabel, let accountID, let context = labelContext(row.deviceID),
              let m = try? master.masterKey(for: accountID), let v = try? vault.masterKey(for: accountID),
              let data = try? PrivateDataCrypto.openDouble(envelope, outer: m, inner: v, context: context)
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// The device's name (such as "iPad"), double-encrypted like everything else.
    private func saveLabel(for device: UUID, client: SupabaseClient) async {
        guard let accountID, let context = labelContext(device),
              let m = try? master.masterKey(for: accountID), let v = try? vault.masterKey(for: accountID),
              let envelope = try? PrivateDataCrypto.sealDouble(Data(UIDevice.current.model.utf8), outer: m, inner: v, context: context)
        else { return }
        _ = try? await client.from(Self.devicesTable)
            .update(LabelUpdate(encryptedLabel: envelope))
            .eq("user_id", value: accountID.uuidString.lowercased())
            .eq("device_id", value: device.uuidString.lowercased())
            .execute()
    }

    /// Seals the account's keys to a waiting device. The caller confirms the
    /// twelve-digit code and the person's identity first.
    func approve(_ device: LinkedDevice) async throws {
        guard state == .ready, let accountID, let client = client(for: accountID) else { throw AuthError.network }
        let rows: [DeviceRow] = try await client.from(Self.devicesTable)
            .select("user_id,device_id,public_wrapping_key,encrypted_label,created_at")
            .eq("user_id", value: accountID.uuidString.lowercased())
            .eq("device_id", value: device.id.uuidString.lowercased())
            .execute().value
        // The code is recomputed from what the server holds now, so a key
        // swapped after the person compared codes is refused.
        guard let publicKey = rows.first?.publicWrappingKey,
              DeviceKeyEnvelope.safetyCode(deviceID: device.id, publicKey: publicKey) == device.safetyCode
        else { throw AuthError.serverRejected(String(localized: "Code changed. Don't approve.")) }
        try await sealKeys(to: device.id, publicKey: publicKey, client: client)
        await refreshDevices()
    }

    /// Removes a device from the list. It stops that device from being
    /// approved; keys it already received stay on it until "Start over".
    func remove(_ device: LinkedDevice) async throws {
        guard let accountID, let client = client(for: accountID) else { throw AuthError.network }
        try await client.from(Self.devicesTable).delete()
            .eq("user_id", value: accountID.uuidString.lowercased())
            .eq("device_id", value: device.id.uuidString.lowercased())
            .execute()
        await refreshDevices()
    }

    /// For when no device with the keys is left: erases the encrypted data
    /// nobody can open any more, forgets every device, and makes new keys here.
    func startOver() async throws {
        guard let accountID, let client = client(for: accountID) else { throw AuthError.network }
        let failed = await PrivateDataStore(client: client).eraseAllUserData(for: accountID)
        guard failed.isEmpty else { throw AuthError.serverRejected(String(localized: "Couldn't erase. Try again.")) }
        guard let identity = try? DeviceIdentity.load(for: accountID) else { throw AuthError.storageFailure }
        await becomeFirstDevice(accountID, identity: identity, client: client, version: 1)
        guard state == .ready else { throw AuthError.network }
    }
}
