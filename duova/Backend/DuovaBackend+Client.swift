import Foundation
import Supabase

extension DuovaBackend {
    /// The one shared Supabase client, or nil when the project isn't
    /// configured (no `DuovaDev.xcconfig`). Its session is kept in the Keychain
    /// by the SDK. Duova works as a local-only app when this is nil.
    static let client: SupabaseClient? = try? makeClient()

    static var isConfigured: Bool { client != nil }
}
