import Foundation

/// What the companion pane is showing: a context the person opened from the
/// primary surface through the site's own links.
enum CompanionKind: String, Codable, CaseIterable {
    case post, comments, profile, explore, messages, other
}

/// Everything the engine needs to know about one social website, so the same
/// host, panes, checkpoints and restore logic work for any service. Each
/// adapter is tied to exact hosts and versioned, and nothing in it invents
/// content: it only names the site's real routes.
protocol SocialAdapter {
    var service: ServiceID { get }
    /// Bumped whenever routes, scripts or styles change, so checkpoints and
    /// injected code from an older adapter can be told apart.
    var version: Int { get }
    /// The site's front page; where the primary surface starts and falls back to.
    var homeURL: URL { get }
    /// Exact hosts the site lives on. Main-frame navigations stay within these.
    var siteHosts: Set<String> { get }
    /// Exact hosts of sign-in pages the site hands off to (and back from).
    var authHosts: Set<String> { get }
    /// Narrowest pane that should still ask for the desktop site.
    var desktopMinimumWidth: CGFloat { get }
    /// A responsive phone source remains consistent when folding a live page.
    var prefersMobileContent: Bool { get }
    func permitsPrefetch(_ url: URL) -> Bool
    func acceptsCompanion(_ kind: CompanionKind, url: URL) -> Bool
    func companionPresentationScript(for kind: CompanionKind) -> String

    /// A route safe to remember: the path only, with nothing that identifies a
    /// session, a code or a search. Nil when the page shouldn't be remembered.
    func checkpointRoute(for url: URL) -> String?
    /// Turns a remembered route back into a URL on the site, or nil if it's no
    /// longer a route this adapter trusts.
    func url(forCheckpointRoute route: String) -> URL?
    /// Which companion context a link opens, or nil when the primary surface
    /// should handle it itself.
    func companionKind(for url: URL, from primary: URL?) -> CompanionKind?

    /// JavaScript the engine injects into the primary surface at document
    /// start, in its own content world. Must be read-only apart from
    /// forwarding chosen link taps. Empty when the adapter has nothing to add.
    var primaryScript: String { get }
    /// Minimal CSS (spacing and overflow only, never colors or branding), or
    /// nil. Injected only on `siteHosts`.
    var styleSheet: String? { get }
    /// JavaScript that returns the permalink path of the content nearest the
    /// top of the viewport, or null. Used only to remember where the person was.
    var anchorScript: String { get }
    /// JavaScript that, given an anchor path, scrolls it into view and returns
    /// true if it was found.
    func scrollToAnchorScript(_ anchor: String) -> String
}

extension SocialAdapter {
    var desktopMinimumWidth: CGFloat { 700 }
    var prefersMobileContent: Bool { false }
    func permitsPrefetch(_ url: URL) -> Bool { false }
    func companionPresentationScript(for kind: CompanionKind) -> String { "true" }
    func acceptsCompanion(_ kind: CompanionKind, url: URL) -> Bool {
        companionKind(for: url, from: nil) == kind
    }
    var primaryScript: String { "" }
    var styleSheet: String? { nil }
    var anchorScript: String { "null" }
    func scrollToAnchorScript(_ anchor: String) -> String { "false" }
    func companionKind(for url: URL, from primary: URL?) -> CompanionKind? { nil }

    /// Exact-host check (never a substring match) for the site and its sign-in pages.
    func allowsMainFrame(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased() else { return false }
        return siteHosts.contains(host) || authHosts.contains(host)
    }

    func isSiteHost(_ url: URL?) -> Bool {
        guard url?.scheme?.lowercased() == "https", url?.user == nil, url?.password == nil,
              url?.port == nil || url?.port == 443,
              let host = url?.host()?.lowercased() else { return false }
        return siteHosts.contains(host)
    }
}

/// The baseline for any social site that opens inside Duova: the real site,
/// its own navigation, one or two panes, remembered routes, and nothing else.
struct GenericSocialAdapter: SocialAdapter {
    let service: ServiceID
    let version = 1
    let homeURL: URL
    let siteHosts: Set<String>
    let authHosts: Set<String>

    init(service: ServiceID, homeURL: URL, siteHosts: Set<String>, authHosts: Set<String> = []) {
        self.service = service
        self.homeURL = homeURL
        self.siteHosts = Set(siteHosts.map { $0.lowercased() })
        self.authHosts = Set(authHosts.map { $0.lowercased() })
    }

    func checkpointRoute(for url: URL) -> String? {
        guard isSiteHost(url) else { return nil }
        return SocialRoutes.pathOnly(url)
    }

    func url(forCheckpointRoute route: String) -> URL? {
        SocialRoutes.url(path: route, on: homeURL)
    }
}

/// Shared route helpers.
enum SocialRoutes {
    /// The path alone: no query (search terms, share tokens, codes) and no fragment.
    static func pathOnly(_ url: URL) -> String? {
        let path = url.path(percentEncoded: false)
        guard path.hasPrefix("/"), path.count <= 512, !path.contains("..") else { return nil }
        return path
    }

    static func url(path: String, on home: URL) -> URL? {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), path.count <= 512,
              !path.contains(".."), !path.contains("\\\\"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = home.host()
        components.path = path
        return components.url
    }
}

/// Which adapter opens which service. A service without an adapter can't be launched.
enum SocialAdapterRegistry {
    static func adapter(for service: ServiceID) -> (any SocialAdapter)? {
        switch service {
        case .instagram:
            return InstagramAdapter()
        default:
            // Other services join here once their sites are reviewed; none
            // opens yet, so their cards stay honest about that.
            return nil
        }
    }
}
