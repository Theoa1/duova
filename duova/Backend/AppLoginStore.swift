import CryptoKit
import Foundation
import Supabase

/// How someone signs in to an app inside Duova.
enum AppLoginMethod: String, PreferenceOption {
    case emailPassword, usernamePassword, apple, google, microsoft, facebook, sso, passkey, appManaged

    var title: String {
        switch self {
        case .emailPassword: String(localized: "Email & password")
        case .usernamePassword: String(localized: "Username & password")
        case .apple: String(localized: "Sign in with Apple")
        case .google: String(localized: "Google")
        case .microsoft: String(localized: "Microsoft")
        case .facebook: String(localized: "Facebook")
        case .sso: String(localized: "Work or school (SSO)")
        case .passkey: String(localized: "Passkey")
        case .appManaged: String(localized: "The app's own sign-in")
        }
    }

    /// Only these keep a password; the others sign in through someone else.
    var usesPassword: Bool { self == .emailPassword || self == .usernamePassword }

    var identifierTitle: String {
        switch self {
        case .usernamePassword: String(localized: "Username")
        case .emailPassword: String(localized: "Email")
        default: String(localized: "Account email (optional)")
        }
    }
}

/// How an app delivers its one-time code, if it sends one. The code itself is
/// never saved.
enum CodeDelivery: String, PreferenceOption {
    case none, email, sms, authenticatorApp, prompt

    var title: String {
        switch self {
        case .none: String(localized: "No code")
        case .email: String(localized: "Email")
        case .sms: String(localized: "Text message")
        case .authenticatorApp: String(localized: "Authenticator app")
        case .prompt: String(localized: "Prompt on another device")
        }
    }
}

struct AppLogin: Equatable {
    var method: AppLoginMethod = .emailPassword
    var identifier = ""
    var password = ""
    var codeDelivery: CodeDelivery = .none
}

/// Saved app logins and cached app sessions for one account. Cached sessions
/// (an app's cookies) never leave this device.
///
/// Every field is a separate `dv2` envelope (ChaCha20-Poly1305 inside
/// AES-256-GCM, two independent device-only keys, bound to user/app/field).
/// On the device those envelopes are stored again inside `SecureStore`
/// (AES-256-GCM with its own Keychain key, under iOS file protection). In the
/// cloud they go to `duova_app_credentials`, which accepts only `dv2` text and
/// keys rows by an opaque HMAC instead of the app's name.
struct AppLoginStore {
    private static let table = "duova_app_credentials"
    private static let fields = ["app_slug_enc", "auth_method_enc", "login_identifier_enc", "secret_enc", "code_delivery_enc"]

    private struct Stored: Codable {
        var envelopes: [String: String]
        var sessionCachedAt: Date?
    }

    let accountID: UUID
    private let store: SecureStore
    private let master: SymmetricKey
    private let vault: SymmetricKey

    init(accountID: UUID, store: SecureStore = .shared) throws {
        self.accountID = accountID
        self.store = store
        master = try KeychainKeyProvider().masterKey(for: accountID)
        vault = try KeychainKeyProvider.vault.masterKey(for: accountID)
    }

    private var userKey: String { accountID.uuidString.lowercased() }
    /// The app's opaque per-account reference (never its name).
    func reference(_ slug: String) -> String {
        PrivateDataCrypto.appReference(for: slug, masterKey: master, userID: accountID)
    }
    private func localName(_ slug: String) -> String {
        "app-login-\(accountID.uuidString)-\(reference(slug))"
    }
    private func context(_ ref: String, _ column: String) -> EnvelopeContext {
        EnvelopeContext(userID: accountID, table: Self.table, recordID: ref, column: column)
    }
    private func seal(_ data: Data, ref: String, column: String) throws -> String {
        try PrivateDataCrypto.sealDouble(data, outer: master, inner: vault, context: context(ref, column))
    }
    private func open(_ envelope: String, ref: String, column: String) throws -> Data {
        try PrivateDataCrypto.openDouble(envelope, outer: master, inner: vault, context: context(ref, column))
    }

    /// The cloud client, only while it's signed in as this account.
    private var client: SupabaseClient? {
        guard let client = DuovaBackend.client, client.auth.currentUser?.id == accountID else { return nil }
        return client
    }

    // MARK: Login

    func login(for slug: String) -> AppLogin? {
        guard let stored = store.load(Stored.self, name: localName(slug)) else { return nil }
        return try? decode(stored.envelopes, ref: reference(slug))
    }

    private func decode(_ envelopes: [String: String], ref: String) throws -> AppLogin? {
        func text(_ column: String) throws -> String? {
            try envelopes[column].map { String(decoding: try open($0, ref: ref, column: column), as: UTF8.self) }
        }
        guard let method = try text("auth_method_enc").flatMap(AppLoginMethod.init(rawValue:)) else { return nil }
        return AppLogin(
            method: method,
            identifier: try text("login_identifier_enc") ?? "",
            password: try text("secret_enc") ?? "",
            codeDelivery: try text("code_delivery_enc").flatMap(CodeDelivery.init(rawValue:)) ?? .none)
    }

    /// Saves on the device, then to the cloud when signed in. Returns whether
    /// the cloud copy was updated.
    @discardableResult
    func save(_ login: AppLogin, for slug: String) async throws -> Bool {
        let ref = reference(slug)
        var envelopes: [String: String] = [
            "app_slug_enc": try seal(Data(slug.utf8), ref: ref, column: "app_slug_enc"),
            "auth_method_enc": try seal(Data(login.method.rawValue.utf8), ref: ref, column: "auth_method_enc"),
            "code_delivery_enc": try seal(Data(login.codeDelivery.rawValue.utf8), ref: ref, column: "code_delivery_enc"),
        ]
        let identifier = login.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if !identifier.isEmpty {
            envelopes["login_identifier_enc"] = try seal(Data(identifier.utf8), ref: ref, column: "login_identifier_enc")
        }
        if login.method.usesPassword, !login.password.isEmpty {
            envelopes["secret_enc"] = try seal(Data(login.password.utf8), ref: ref, column: "secret_enc")
        }

        var stored = store.load(Stored.self, name: localName(slug)) ?? Stored(envelopes: [:])
        let session = stored.envelopes["session_cache_enc"]
        stored.envelopes = envelopes
        if let session { stored.envelopes["session_cache_enc"] = session }
        try store.save(stored, name: localName(slug))

        guard let client else { return false }
        var row: [String: String?] = ["user_id": userKey, "app_ref": ref]
        for field in Self.fields { row.updateValue(envelopes[field], forKey: field) }
        do {
            try await client.from(Self.table).upsert(row, onConflict: "user_id,app_ref").execute()
            return true
        } catch {
            return false
        }
    }

    /// Fetches the cloud copy when this device has none (and can open it).
    func restoreFromCloud(for slug: String) async -> AppLogin? {
        guard let client else { return nil }
        let ref = reference(slug)
        let rows: [[String: String?]]
        do {
            rows = try await client.from(Self.table)
                .select(Self.fields.joined(separator: ","))
                .eq("user_id", value: userKey).eq("app_ref", value: ref).execute().value
        } catch {
            return nil
        }
        guard let row = rows.first else { return nil }
        let envelopes = row.compactMapValues { $0 }
        guard let login = try? decode(envelopes, ref: ref) else { return nil }
        try? store.save(Stored(envelopes: envelopes), name: localName(slug))
        return login
    }

    /// The references of every app with a saved login in the cloud, or nil offline.
    func cloudReferences() async -> Set<String>? {
        guard let client else { return nil }
        let rows: [[String: String]]? = try? await client.from(Self.table)
            .select("app_ref").eq("user_id", value: userKey).execute().value
        return rows.map { Set($0.compactMap { $0["app_ref"] }) }
    }

    func remove(for slug: String) async {
        store.remove(name: localName(slug))
        guard let client else { return }
        _ = try? await client.from(Self.table).delete()
            .eq("user_id", value: userKey).eq("app_ref", value: reference(slug)).execute()
    }

    // MARK: Cached app session

    /// Keeps an app's signed-in state (for example its cookies) on this device
    /// so it opens signed in. Sealed exactly like the password.
    func saveSessionCache(_ data: Data, for slug: String) throws {
        let ref = reference(slug)
        let envelope = try seal(data, ref: ref, column: "session_cache_enc")
        var stored: Stored
        if let existing = store.load(Stored.self, name: localName(slug)) {
            stored = existing
        } else {
            stored = Stored(envelopes: [
                "app_slug_enc": try seal(Data(slug.utf8), ref: ref, column: "app_slug_enc"),
                "auth_method_enc": try seal(Data(AppLoginMethod.appManaged.rawValue.utf8), ref: ref, column: "auth_method_enc"),
            ])
        }
        stored.envelopes["session_cache_enc"] = envelope
        stored.sessionCachedAt = .now
        try store.save(stored, name: localName(slug))
    }

    /// Forgets an app's signed-in state; the saved login stays.
    func clearSessionCache(for slug: String) {
        guard var stored = store.load(Stored.self, name: localName(slug)) else { return }
        stored.envelopes["session_cache_enc"] = nil
        stored.sessionCachedAt = nil
        try? store.save(stored, name: localName(slug))
    }

    func sessionCache(for slug: String) -> Data? {
        guard let envelope = store.load(Stored.self, name: localName(slug))?.envelopes["session_cache_enc"] else {
            return nil
        }
        return try? open(envelope, ref: reference(slug), column: "session_cache_enc")
    }
}
