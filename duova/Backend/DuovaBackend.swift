import Foundation
import Supabase

enum DuovaBackend {

    enum ConfigurationError: LocalizedError {
        case invalidURL
        case invalidPublishableKey

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Missing or invalid Supabase URL."
            case .invalidPublishableKey:
                return "Missing or invalid publishable key."
            }
        }
    }

    static func credentials() throws -> (url: URL, key: String) {
        guard
            let urlString = Bundle.main.object(
                forInfoDictionaryKey: "DUOVA_SUPABASE_URL"
            ) as? String,
            let url = URL(string: urlString),
            url.scheme == "https",
            let host = url.host,
            host.hasSuffix(".supabase.co")
        else {
            throw ConfigurationError.invalidURL
        }

        guard
            let key = Bundle.main.object(
                forInfoDictionaryKey: "DUOVA_SUPABASE_PUBLISHABLE_KEY"
            ) as? String,
            key.hasPrefix("sb_publishable_")
        else {
            throw ConfigurationError.invalidPublishableKey
        }

        return (url, key)
    }

    static func makeClient() throws -> SupabaseClient {
        let configuration = try credentials()

        return SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.key,
            options: SupabaseClientOptions(auth: .init(storage: DuovaAuthStorage.shared))
        )
    }
}
