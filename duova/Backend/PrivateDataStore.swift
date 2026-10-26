import Foundation
import Supabase

/// What the cloud holds for the signed-in person's encrypted display name.
nonisolated enum CloudNameState: Equatable, Sendable {
    /// No name has been uploaded yet.
    case empty
    /// A name was uploaded and this device's key opened it.
    case name(String)
    /// A name exists but this device's key can't open it (it was sealed on
    /// another device). It must never be overwritten from here.
    case sealedElsewhere
}

/// Reads and writes private Duova data. Everything private is sealed on this
/// device with `PrivateDataCrypto` before it leaves, and opened here after it
/// arrives; the server only ever stores `dv1:` envelopes.
nonisolated struct PrivateDataStore: Sendable {
    let client: SupabaseClient
    let keys: any PrivateKeyProviding
    let vaultKeys: any PrivateKeyProviding

    init(
        client: SupabaseClient, keys: any PrivateKeyProviding = KeychainKeyProvider(),
        vaultKeys: any PrivateKeyProviding = KeychainKeyProvider.vault
    ) {
        self.client = client
        self.keys = keys
        self.vaultKeys = vaultKeys
    }

    /// New data is always written double-encrypted (dv2); older dv1 values still open.
    private func seal(_ text: String, user: UUID, context: EnvelopeContext) throws -> String {
        try PrivateDataCrypto.sealDouble(
            Data(text.utf8), outer: keys.masterKey(for: user), inner: vaultKeys.masterKey(for: user), context: context)
    }

    private func open(_ envelope: String, user: UUID, context: EnvelopeContext) throws -> String {
        if envelope.hasPrefix("\(PrivateDataCrypto.doubleTag):") {
            let data = try PrivateDataCrypto.openDouble(
                envelope, outer: keys.masterKey(for: user), inner: vaultKeys.masterKey(for: user), context: context)
            return String(decoding: data, as: UTF8.self)
        }
        return try PrivateDataCrypto.open(String.self, from: envelope, using: keys.masterKey(for: user), context: context)
    }

    private static let profiles = "duova_profiles"
    private static let notes = "duova_notes"

    // MARK: Display name

    private struct ProfileRow: Decodable {
        let displayNameEncrypted: String?
        enum CodingKeys: String, CodingKey { case displayNameEncrypted = "display_name_encrypted" }
    }

    private struct ProfileUpdate: Encodable {
        let displayNameEncrypted: String
        enum CodingKeys: String, CodingKey { case displayNameEncrypted = "display_name_encrypted" }
    }

    private struct ProfileUpsert: Encodable {
        let userID: UUID
        let displayNameEncrypted: String
        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case displayNameEncrypted = "display_name_encrypted"
        }
    }

    private func nameContext(_ user: UUID) -> EnvelopeContext {
        EnvelopeContext(userID: user, table: Self.profiles, recordID: user.uuidString.lowercased(),
                        column: "display_name_encrypted")
    }

    /// The raw stored envelope, for verification.
    func rawDisplayName(for user: UUID) async throws -> String? {
        let rows: [ProfileRow] = try await client.from(Self.profiles)
            .select("display_name_encrypted")
            .eq("user_id", value: user.uuidString.lowercased())
            .execute()
            .value
        return rows.first?.displayNameEncrypted
    }

    func displayName(for user: UUID) async throws -> CloudNameState {
        guard let envelope = try await rawDisplayName(for: user), !envelope.isEmpty else {
            return .empty
        }
        do {
            return .name(try open(envelope, user: user, context: nameContext(user)))
        } catch PrivateDataError.keyUnavailable, PrivateDataError.authenticationFailed {
            return .sealedElsewhere
        }
    }

    /// Seals and saves the name. Refuses to replace a name this device can't
    /// open, so two devices can never overwrite each other's data.
    @discardableResult
    func saveDisplayName(_ name: String, for user: UUID) async throws -> Bool {
        if case .sealedElsewhere = try await displayName(for: user) { return false }
        let envelope = try seal(name, user: user, context: nameContext(user))
        // Upsert: the profile row is created at sign-up, but erasing an account's
        // data removes it, and signing back in must be able to recreate it.
        try await client.from(Self.profiles)
            .upsert(ProfileUpsert(userID: user, displayNameEncrypted: envelope), onConflict: "user_id")
            .execute()
        return true
    }

    // MARK: Notes

    private struct NoteRow: Decodable {
        let id: UUID
        let userID: UUID
        let encryptedPayload: String
        enum CodingKeys: String, CodingKey {
            case id
            case userID = "user_id"
            case encryptedPayload = "encrypted_payload"
        }
    }

    private struct NoteInsert: Encodable {
        let id: UUID
        let userID: UUID
        let encryptedPayload: String
        enum CodingKeys: String, CodingKey {
            case id
            case userID = "user_id"
            case encryptedPayload = "encrypted_payload"
        }
    }

    private func noteContext(user: UUID, note: UUID) -> EnvelopeContext {
        EnvelopeContext(userID: user, table: Self.notes, recordID: note.uuidString.lowercased(),
                        column: "encrypted_payload")
    }

    /// Seals and stores a private note. The record id is chosen before
    /// sealing because it's bound into the envelope.
    func createNote(_ text: String, for user: UUID) async throws -> UUID {
        let id = UUID()
        let envelope = try seal(text, user: user, context: noteContext(user: user, note: id))
        try await client.from(Self.notes)
            .insert(NoteInsert(id: id, userID: user, encryptedPayload: envelope))
            .execute()
        return id
    }

    /// The raw stored envelope for a note, or nil if it isn't visible to the caller.
    func rawNote(_ id: UUID) async throws -> String? {
        let rows: [NoteRow] = try await client.from(Self.notes)
            .select("id, user_id, encrypted_payload")
            .eq("id", value: id.uuidString.lowercased())
            .execute()
            .value
        return rows.first?.encryptedPayload
    }

    func note(_ id: UUID, for user: UUID) async throws -> String? {
        guard let envelope = try await rawNote(id) else { return nil }
        return try open(envelope, user: user, context: noteContext(user: user, note: id))
    }

    /// Ids of every note row the caller can see (row-level security limits
    /// this to their own).
    func visibleNoteIDs() async throws -> [UUID] {
        let rows: [NoteRow] = try await client.from(Self.notes)
            .select("id, user_id, encrypted_payload")
            .execute()
            .value
        return rows.map(\.id)
    }

    func deleteNote(_ id: UUID) async throws {
        try await client.from(Self.notes)
            .delete()
            .eq("id", value: id.uuidString.lowercased())
            .execute()
    }

    /// Attempts to write a note row owned by someone else. Returns normally
    /// only if the database accepted it, which row-level security must prevent.
    func insertNoteClaiming(id: UUID = UUID(), owner: UUID, envelope: String) async throws {
        try await client.from(Self.notes)
            .insert(NoteInsert(id: id, userID: owner, encryptedPayload: envelope))
            .execute()
    }

    /// Row-level update of someone else's profile. Returns how many rows
    /// the database actually changed.
    func updateProfileEnvelope(of user: UUID, to envelope: String) async throws -> Int {
        let changed: [ProfileRow] = try await client.from(Self.profiles)
            .update(ProfileUpdate(displayNameEncrypted: envelope))
            .eq("user_id", value: user.uuidString.lowercased())
            .select("display_name_encrypted")
            .execute()
            .value
        return changed.count
    }

    func deleteNoteReturningCount(_ id: UUID) async throws -> Int {
        let removed: [NoteRow] = try await client.from(Self.notes)
            .delete()
            .eq("id", value: id.uuidString.lowercased())
            .select("id, user_id, encrypted_payload")
            .execute()
            .value
        return removed.count
    }

    // MARK: Erase

    /// Deletes everything the signed-in person can delete from the cloud, in
    /// dependency order, including every device and its sealed copy of the
    /// keys (schema v4). App suggestions are kept. Returns the tables that
    /// couldn't be cleared.
    func eraseAllUserData(for user: UUID) async -> [String] {
        let tables = [
            "duova_app_credentials", "duova_user_app_preferences", "duova_user_preferences",
            "duova_workspace_panes", "duova_user_workspaces", "duova_note_app_links", "duova_notes",
            "duova_vault_items", "duova_user_app_state", "duova_user_app_library",
            "duova_user_settings", "duova_profiles",
            "duova_user_key_envelopes", "duova_user_devices",
        ]
        var failed: [String] = []
        for table in tables {
            do {
                try await client.from(table).delete()
                    .eq("user_id", value: user.uuidString.lowercased())
                    .execute()
            } catch {
                failed.append(table)
            }
        }
        keys.removeKey(for: user)
        vaultKeys.removeKey(for: user)
        DeviceIdentity.remove(for: user)
        return failed
    }
}
