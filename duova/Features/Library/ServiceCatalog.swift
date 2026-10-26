import SwiftUI

/// Library categories, in the order defined by the product blueprint.
/// "Favorites" and "Recently used" are virtual filters, not categories.
enum ServiceCategory: String, CaseIterable, Identifiable, Hashable {
    case social
    case streaming
    case activity
    case maps
    case food
    case fashion
    case productivity
    case other

    var id: String { rawValue }

    /// Short name used by filter chips.
    var title: String {
        switch self {
        case .social: String(localized: "Social")
        case .streaming: String(localized: "Streaming")
        case .activity: String(localized: "Activity")
        case .maps: String(localized: "Maps")
        case .food: String(localized: "Food")
        case .fashion: String(localized: "Fashion")
        case .productivity: String(localized: "Productivity")
        case .other: String(localized: "Other")
        }
    }

    /// Full name used in rows and detail views.
    var longTitle: String {
        switch self {
        case .social: String(localized: "Social")
        case .streaming: String(localized: "Streaming & Entertainment")
        case .activity: String(localized: "Activity & Fitness")
        case .maps: String(localized: "Maps & Travel")
        case .food: String(localized: "Food & Delivery")
        case .fashion: String(localized: "Fashion & Shopping")
        case .productivity: String(localized: "Productivity")
        case .other: String(localized: "Other")
        }
    }

    var symbol: String {
        switch self {
        case .social: "bubble.left.and.bubble.right.fill"
        case .streaming: "play.rectangle.fill"
        case .activity: "figure.run"
        case .maps: "map.fill"
        case .food: "fork.knife"
        case .fashion: "bag.fill"
        case .productivity: "doc.text.fill"
        case .other: "square.grid.2x2.fill"
        }
    }
}

/// Compatibility status taxonomy from the blueprint. Nothing is compatibility
/// certified yet, so every catalog entry is currently `underReview`.
enum CompatibilityStatus: String, CaseIterable {
    case underReview
    case fullOptimization
    case enhancedWeb
    case limitedWeb
    case nativeHandoff
    case unsupported

    var title: String {
        switch self {
        case .underReview: String(localized: "Under review")
        case .fullOptimization: String(localized: "Full optimization")
        case .enhancedWeb: String(localized: "Enhanced web")
        case .limitedWeb: String(localized: "Limited web")
        case .nativeHandoff: String(localized: "Native handoff")
        case .unsupported: String(localized: "Unsupported")
        }
    }

    var explanation: String {
        switch self {
        case .underReview:
            String(localized: "Duova has not completed a capability, permission, and branding assessment for this service, so it cannot be opened yet.")
        case .fullOptimization:
            String(localized: "The listed key journeys have been verified in an adapted workspace.")
        case .enhancedWeb:
            String(localized: "A usable website with tested improvements.")
        case .limitedWeb:
            String(localized: "The website has known significant limitations. Details are shown before opening.")
        case .nativeHandoff:
            String(localized: "An embedded experience is not suitable. Duova hands off to the official app or browser.")
        case .unsupported:
            String(localized: "This service is unavailable, unsafe, or not permitted.")
        }
    }

    var symbol: String {
        switch self {
        case .underReview: "hourglass"
        case .fullOptimization: "checkmark.seal.fill"
        case .enhancedWeb: "sparkles"
        case .limitedWeb: "exclamationmark.triangle.fill"
        case .nativeHandoff: "arrow.up.forward.app.fill"
        case .unsupported: "nosign"
        }
    }

    var tint: Color {
        switch self {
        // Under review is a neutral, in-progress state, so it uses the brand
        // indigo rather than a warning color.
        case .underReview: DuovaPalette.indigo
        case .fullOptimization: DuovaPalette.emerald
        case .enhancedWeb: DuovaPalette.blue
        case .limitedWeb: DuovaPalette.amber
        case .nativeHandoff: DuovaPalette.teal
        case .unsupported: DuovaPalette.pink
        }
    }
}

/// Stable identifiers for catalog services that currently have a bundled icon.
enum ServiceID: String, CaseIterable, Identifiable, Hashable {
    case instagram
    case youtube
    case spotify
    case googleMaps
    case tiktok
    case gmail
    case whatsapp
    case netflix
    case googleDocs
    case uber

    var id: String { rawValue }
}

struct Service: Identifiable, Hashable {
    let id: ServiceID
    let name: String
    let category: ServiceCategory
    let aliases: [String]
    /// Muted accent used for light trails in the launch animation.
    let accent: Color
    let status: CompatibilityStatus

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        if name.localizedStandardContains(q) { return true }
        if category.longTitle.localizedStandardContains(q) { return true }
        return aliases.contains { $0.localizedStandardContains(q) }
    }
}

/// Bundled catalog. Entries are research candidates drawn from the blueprint's
/// candidate list; none has passed compatibility review.
enum ServiceCatalog {
    /// Ordered so categories alternate. The launch animation uses a prefix of
    /// this list, so the first icons shown are always visually varied.
    static let all: [Service] = [
        Service(id: .instagram, name: "Instagram", category: .social,
                aliases: ["IG", "Insta"], accent: Color(hex: 0xC7678E), status: .underReview),
        Service(id: .youtube, name: "YouTube", category: .streaming,
                aliases: ["YT", "Video"], accent: Color(hex: 0xC96A6A), status: .underReview),
        Service(id: .spotify, name: "Spotify", category: .streaming,
                aliases: ["Music", "Podcasts"], accent: DuovaPalette.emerald, status: .underReview),
        Service(id: .googleMaps, name: "Google Maps", category: .maps,
                aliases: ["Maps", "Navigation"], accent: DuovaPalette.teal, status: .underReview),
        Service(id: .tiktok, name: "TikTok", category: .social,
                aliases: ["Short video"], accent: DuovaPalette.pink, status: .underReview),
        Service(id: .gmail, name: "Gmail", category: .productivity,
                aliases: ["Mail", "Email", "Google Mail"], accent: Color(hex: 0xC76B63), status: .underReview),
        Service(id: .whatsapp, name: "WhatsApp", category: .social,
                aliases: ["Chat", "Messages"], accent: DuovaPalette.emerald, status: .underReview),
        Service(id: .netflix, name: "Netflix", category: .streaming,
                aliases: ["Movies", "Shows"], accent: Color(hex: 0xB85A60), status: .underReview),
        Service(id: .googleDocs, name: "Google Docs", category: .productivity,
                aliases: ["Docs", "Documents"], accent: DuovaPalette.blue, status: .underReview),
        Service(id: .uber, name: "Uber", category: .maps,
                aliases: ["Rides", "Taxi"], accent: DuovaPalette.indigo, status: .underReview)
    ]

    static func service(_ id: ServiceID) -> Service {
        // The catalog is exhaustive over `ServiceID`; a missing entry is a programmer error.
        all.first { $0.id == id } ?? all[0]
    }

    /// The first `count` services, used as the launch-animation icon field.
    static func launchServices(count: Int) -> [Service] {
        Array(all.prefix(max(0, min(count, all.count))))
    }
}
