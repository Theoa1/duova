import Foundation

/// Instagram's real website: its routes, the links that make sense in a
/// companion pane, and the small, reversible script and style that go with it.
///
/// Nothing here changes what Instagram looks like or does. The script only
/// forwards taps on Instagram's own post, profile, Explore and Messages links
/// to the companion pane when there is one; the style only hides scroll bars.
struct InstagramAdapter: SocialAdapter {
    let service = ServiceID.instagram
    let version = 1
    let homeURL = URL(string: "https://www.instagram.com/")!
    let siteHosts: Set<String> = ["www.instagram.com", "instagram.com"]
    let authHosts: Set<String> = [
        "www.facebook.com", "m.facebook.com", "facebook.com", "accounts.instagram.com", "help.instagram.com",
    ]

    /// Kill switch for the injected script and style (adapter-level, versioned).
    static let injectionEnabled = true

    /// First path segments that are Instagram features, not usernames.
    static let reservedSegments: Set<String> = [
        "accounts", "explore", "reels", "reel", "p", "direct", "stories", "about", "legal", "developer",
        "api", "graphql", "challenge", "emails", "session", "web", "ajax", "static", "privacy", "terms",
        "press", "create", "settings", "nametag", "lite", "your_activity", "archive", "saved", "tags",
        "locations", "igtv", "tv", "guide", "oauth", "linkshim", "directory", "blog", "help", "ads",
        "business", "download", "invites", "qr", "s", "sem", "topics", "tv", "u",
    ]

    /// Classifies a path on the site the same way the injected script does.
    static func kind(ofPath path: String) -> CompanionKind? {
        let segments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let first = segments.first else { return nil }
        switch first {
        case "p", "reel":
            return segments.count >= 2 ? .post : nil
        case "explore":
            return .explore
        case "direct":
            return .messages
        default:
            guard !reservedSegments.contains(first), isUsername(first) else { return nil }
            // /username/, /username/reels/, /username/tagged/
            if segments.count == 1 { return .profile }
            if segments.count == 2, ["reels", "tagged", "saved", "channel"].contains(segments[1]) { return .profile }
            return nil
        }
    }

    private static func isUsername(_ text: String) -> Bool {
        (1...30).contains(text.count) && text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }
    }

    func companionKind(for url: URL, from primary: URL?) -> CompanionKind? {
        guard isSiteHost(url) else { return nil }
        return Self.kind(ofPath: url.path(percentEncoded: false))
    }

    func checkpointRoute(for url: URL) -> String? {
        guard isSiteHost(url), let path = SocialRoutes.pathOnly(url) else { return nil }
        let first = path.split(separator: "/", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        switch first {
        case "accounts", "challenge", "emails", "session", "oauth", "linkshim":
            // Sign-in, recovery and checks: never a place to return to.
            return nil
        case "direct":
            // A thread path names a conversation; remember only the inbox.
            return "/direct/inbox/"
        case "stories":
            return "/"
        default:
            return path
        }
    }

    func url(forCheckpointRoute route: String) -> URL? {
        guard let url = SocialRoutes.url(path: route, on: homeURL), checkpointRoute(for: url) != nil else { return nil }
        return url
    }

    // MARK: Injection (version 1)

    var styleSheet: String? {
        guard Self.injectionEnabled else { return nil }
        return """
        /* duova instagram v1: scroll bars only; colors, fonts and layout are Instagram's */
        ::-webkit-scrollbar { display: none; width: 0; height: 0; }
        """
    }

    var primaryScript: String {
        guard Self.injectionEnabled else { return "" }
        let reserved = Self.reservedSegments.sorted().map { "\"\($0)\"" }.joined(separator: ",")
        return """
        (function () {
          if (window.__duovaInstalled) { return; }
          window.__duovaInstalled = true;
          if (typeof window.__duovaCompanion !== 'boolean') { window.__duovaCompanion = false; }
          var HOSTS = ['www.instagram.com', 'instagram.com'];
          if (HOSTS.indexOf(location.host) < 0) { return; }
          var RESERVED = [\(reserved)];
          var CONTEXT = ['reels', 'tagged', 'saved', 'channel'];
          function isUser(s) { return s.length >= 1 && s.length <= 30 && /^[A-Za-z0-9._]+$/.test(s); }
          function kind(path) {
            var seg = path.split('/').filter(function (s) { return s.length > 0; });
            if (seg.length === 0) { return null; }
            var first = seg[0];
            if (first === 'p' || first === 'reel') { return seg.length >= 2 ? 'post' : null; }
            if (first === 'explore') { return 'explore'; }
            if (first === 'direct') { return 'messages'; }
            if (RESERVED.indexOf(first) >= 0 || !isUser(first)) { return null; }
            if (seg.length === 1) { return 'profile'; }
            if (seg.length === 2 && CONTEXT.indexOf(seg[1]) >= 0) { return 'profile'; }
            return null;
          }
          document.addEventListener('click', function (e) {
            if (!window.__duovaCompanion) { return; }
            if (e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) { return; }
            var t = e.target;
            var a = (t && t.closest) ? t.closest('a[href]') : null;
            if (!a) { return; }
            var url;
            try { url = new URL(a.getAttribute('href'), location.href); } catch (err) { return; }
            if (url.host !== location.host) { return; }
            var k = kind(url.pathname);
            if (!k) { return; }
            e.preventDefault();
            e.stopImmediatePropagation();
            try {
              window.webkit.messageHandlers.duova.postMessage({ type: 'open', path: url.pathname, kind: k });
            } catch (err) {}
          }, true);
        })();
        """
    }

    var anchorScript: String {
        """
        (function () {
          var best = null, bestTop = Infinity;
          var items = document.querySelectorAll('article');
          for (var i = 0; i < items.length; i++) {
            var r = items[i].getBoundingClientRect();
            if (r.bottom <= 0) { continue; }
            var d = Math.abs(r.top);
            if (d < bestTop) { bestTop = d; best = items[i]; }
          }
          if (!best) { return null; }
          var a = best.querySelector('a[href^="/p/"], a[href^="/reel/"]');
          return a ? a.getAttribute('href') : null;
        })()
        """
    }

    func scrollToAnchorScript(_ anchor: String) -> String {
        guard let encoded = try? JSONEncoder().encode(anchor), let literal = String(data: encoded, encoding: .utf8) else {
            return "false"
        }
        return """
        (function () {
          var a = document.querySelector('article a[href=\(literal)]');
          if (!a) { return false; }
          var el = a.closest('article') || a;
          el.scrollIntoView({ block: 'start' });
          return true;
        })()
        """
    }
}
