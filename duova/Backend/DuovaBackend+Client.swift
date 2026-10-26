import Foundation
import Supabase
import Synchronization

extension DuovaBackend {
    /// The one shared Supabase client, or nil when the project isn't
    /// configured (no `DuovaDev.xcconfig`). Its session is kept in the Keychain
    /// by the SDK. Without it nobody can sign in; only previews and tests use
    /// accounts kept on the device (`AuthController(usesCloud: false)`).
    static let client: SupabaseClient? = try? makeClient()

    static var isConfigured: Bool { client != nil }
}

/// The SDK's own Keychain storage (same service and key, so existing sessions
/// carry over), plus a way to put the session away on this device without
/// revoking it on the server: for Face ID / Touch ID sign-in, which keeps the
/// session behind biometrics instead of keeping the password.
nonisolated final class DuovaAuthStorage: AuthLocalStorage {
    static let shared = DuovaAuthStorage()

    private let base = KeychainLocalStorage()
    private let keys = Mutex<Set<String>>([])

    func store(key: String, value: Data) throws {
        keys.withLock { _ = $0.insert(key) }
        try base.store(key: key, value: value)
    }

    func retrieve(key: String) throws -> Data? {
        keys.withLock { _ = $0.insert(key) }
        return try base.retrieve(key: key)
    }

    func remove(key: String) throws {
        try base.remove(key: key)
    }

    /// Forgets the session here. The server still accepts it, so only do this
    /// after keeping it somewhere safe, or once the account is gone.
    func forgetLocally() {
        for key in keys.withLock({ $0 }) { try? base.remove(key: key) }
    }
}
