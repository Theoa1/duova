import Foundation
import Supabase

/// A category row from `duova_categories`.
nonisolated struct CloudCategory: Decodable, Identifiable, Hashable, Sendable {
    let slug: String
    let displayName: String
    let sortOrder: Int
    let isVisible: Bool
    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug
        case displayName = "display_name"
        case sortOrder = "sort_order"
        case isVisible = "is_visible"
    }
}

/// An app row from `duova_apps`. Row-level security only returns apps that
/// are published and cleared, so every row decoded here is already visible
/// to signed-in people.
nonisolated struct CloudApp: Decodable, Identifiable, Hashable, Sendable {
    let slug: String
    let displayName: String
    let categorySlug: String
    let officialURL: String
    let capabilityStatus: String
    let isPublished: Bool
    let legalReviewStatus: String
    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug
        case displayName = "display_name"
        case categorySlug = "category_slug"
        case officialURL = "official_url"
        case capabilityStatus = "capability_status"
        case isPublished = "is_published"
        case legalReviewStatus = "legal_review_status"
    }
}

/// Reads the shared app catalog through the authenticated Swift client.
///
/// The catalog is read-only for people: the database gives signed-in users
/// SELECT and nothing else, and anonymous callers no access at all.
nonisolated struct CatalogService: Sendable {
    let client: SupabaseClient

    func categories() async throws -> [CloudCategory] {
        try await client.from("duova_categories")
            .select("slug, display_name, sort_order, is_visible")
            .order("sort_order")
            .execute()
            .value
    }

    func apps() async throws -> [CloudApp] {
        try await client.from("duova_apps")
            .select("slug, display_name, category_slug, official_url, capability_status, is_published, legal_review_status")
            .order("sort_rank")
            .order("display_name")
            .execute()
            .value
    }
}
