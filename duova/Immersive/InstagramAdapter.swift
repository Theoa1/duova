import Foundation

/// Versioned adaptations of Instagram's own routes and semantic controls.
/// Unknown markup falls through to the website; no synthetic content or clicks.
struct InstagramAdapter: SocialAdapter {
    let service = ServiceID.instagram
    let version = 3
    // The mobile website owns all screens; wider panes adapt without a source switch.
    let prefersMobileContent = true
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
        (1...30).contains(text.count) && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_") }
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
            let segments = path.split(separator: "/")
            // A concrete public story reference, never query tokens or a whole tray.
            return segments.count == 3 && Self.isUsername(String(segments[1])) &&
                segments[2].allSatisfy(\.isNumber) ? path : "/"
        default:
            return path == "/" || first == "reels" || Self.kind(ofPath: path) != nil ? path : nil
        }
    }

    func url(forCheckpointRoute route: String) -> URL? {
        guard let url = SocialRoutes.url(path: route, on: homeURL), checkpointRoute(for: url) == route else { return nil }
        return url
    }

    func acceptsCompanion(_ kind: CompanionKind, url: URL) -> Bool {
        guard isSiteHost(url) else { return false }
        return companionKind(for: url, from: nil) == kind ||
            (kind == .comments && Self.kind(ofPath: url.path) == .post)
    }

    func permitsPrefetch(_ url: URL) -> Bool {
        guard isSiteHost(url), url.query == nil, url.fragment == nil else { return false }
        let segments = url.path.split(separator: "/")
        return segments.count == 2 && segments[0] == "p" &&
            segments[1].count <= 64 &&
            segments[1].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    func companionPresentationScript(for kind: CompanionKind) -> String {
        guard Self.injectionEnabled, kind == .comments else { return "true" }
        return #"""
        (() => {
          if (!['www.instagram.com','instagram.com'].includes(location.host) ||
              !/^\/(p|reel)\/[A-Za-z0-9_-]+\//.test(location.pathname)) return false;
          const inputs = document.querySelectorAll('textarea[placeholder],textarea[aria-label]');
          for (const input of inputs) {
            const label = ((input.getAttribute('placeholder') || '') + ' ' +
              (input.getAttribute('aria-label') || '')).toLowerCase();
            if (!/comment|comentario|commentaire|kommentar|commento/.test(label)) continue;
            const region = input.closest('section') || input.closest('form') || input;
            // Reveal Instagram's existing comments region; never focus, type, click or submit.
            region.scrollIntoView({block:'nearest'});
            document.documentElement.dataset.duovaContext = 'comments';
            return true;
          }
          return false;
        })()
        """#
    }

    // MARK: Injection (version 2)

    var styleSheet: String? {
        guard Self.injectionEnabled else { return nil }
        return """
        [data-duova-native-navigation] { display: none !important; }
        /* Compact pages use Instagram's own mobile layout, navigation, dialogs,
           keyboard handling and media sizes. Never resize every image (avatars
           and story tiles are images too), or force nested dialogs to scroll. */
        @media (min-width: 760px) {
          html[data-duova-instagram="3"] main {
            min-width: 0; box-sizing: border-box;
          }
          html[data-duova-instagram="3"] article {
            box-sizing: border-box; min-width: 0;
            max-width: min(100%, 680px); margin-inline: auto;
          }
        }
        """
    }


    /// Recognize only the site's global navigation, never post actions, dialogs or forms.
    /// Attribute writes are excluded from observation, preventing style feedback loops.
    static let navigationScript = #"""
    (() => {
      if (window.__duovaNavigation || location.protocol !== 'https:' ||
          !['www.instagram.com','instagram.com'].includes(location.host)) return;
      window.__duovaNavigation = true;
      let scheduled = false;
      const update = () => {
        scheduled = false;
        if (/^\/(accounts|challenge|oauth|emails|session)(\/|$)/.test(location.pathname)) return;
        const destinations = new Set(['/','/explore/','/reels/','/direct/inbox/']);
        const paths = element => new Set(Array.from(element.querySelectorAll('a[href]')).flatMap(a => {
          try { const u = new URL(a.href,location.href);
            return u.origin === location.origin && destinations.has(u.pathname) ? [u.pathname] : [];
          } catch (_) { return []; }
        }));
        for (const a of Array.from(document.querySelectorAll('a[href]')).slice(0,250)) {
          let node = a.parentElement;
          for (let depth = 0; node && depth < 7 && node !== document.body; depth++, node = node.parentElement) {
            if (node.hasAttribute('data-duova-native-navigation')) break;
            if (node.matches('main,article,form,[role="dialog"]') ||
                node.querySelector('main,article,form,[role="dialog"]')) break;
            if (paths(node).size < 3) continue;
            const r = node.getBoundingClientRect();
            if ((r.height <= 120 && r.width >= innerWidth * 0.5) ||
                (r.width <= 280 && r.height >= innerHeight * 0.5)) {
              node.setAttribute('data-duova-native-navigation','');
              break;
            }
          }
        }
      };
      const schedule = () => {
        if (scheduled || document.hidden) return;
        scheduled = true;
        setTimeout(update,250);
      };
      const observer = new MutationObserver(schedule);
      observer.observe(document.documentElement,{subtree:true,childList:true});
      window.addEventListener('pageshow',schedule);
      schedule();
    })();
    """#

    var primaryScript: String {
        guard Self.injectionEnabled else { return "" }
        let reserved = Self.reservedSegments.sorted().map { "\"\($0)\"" }.joined(separator: ",")
        return #"""
        (() => {
          if (window.__duovaInstalled || location.protocol !== 'https:' ||
              !['www.instagram.com','instagram.com'].includes(location.host)) return;
          window.__duovaInstalled = true;
          window.__duovaCompanion = false;
          const reserved = [\#(reserved)];
          const safeURL = value => {
            try {
              const u = new URL(value, location.href);
              return u.origin === location.origin && !u.username && !u.password ? u : null;
            } catch (_) { return null; }
          };
          const kind = u => {
            const p = u.pathname.split('/').filter(Boolean);
            if (['p','reel'].includes(p[0]) && p.length >= 2) return 'post';
            if (p[0] === 'explore') return 'explore';
            if (p[0] === 'direct') return 'messages';
            if (p[0] && !reserved.includes(p[0]) && /^[A-Za-z0-9._]{1,30}$/.test(p[0]) &&
                (p.length === 1 || (p.length === 2 && ['reels','tagged','saved','channel'].includes(p[1])))) return 'profile';
            return null;
          };
          const commentAction = control => {
            if (!control) return false;
            const labels = [control.getAttribute('aria-label'), control.textContent,
              ...Array.from(control.querySelectorAll('svg[aria-label],svg title')).map(e => e.getAttribute('aria-label') || e.textContent)]
              .filter(Boolean).map(s => s.trim().toLowerCase());
            // Explicit semantic labels, never icon geometry or broad substring matching.
            return labels.some(s => /^(comment|comments|view comments|view all [0-9,.]+ comments|add a comment[.…]*)$/.test(s));
          };
          const context = target => {
            const control = target.closest('a[href],button,[role="button"]');
            if (!control) return null;
            if (commentAction(control)) {
              const article = control.closest('article');
              const link = article && article.querySelector('a[href*="/p/"],a[href*="/reel/"]');
              const u = link ? safeURL(link.href) : safeURL(location.href);
              if (u && kind(u) === 'post') return {url:u,kind:'comments'};
              return null;
            }
            const a = control.closest('a[href]');
            const u = a && safeURL(a.href);
            const k = u && kind(u);
            return k ? {url:u,kind:k} : null;
          };
          document.addEventListener('click', e => {
            if (!e.isTrusted || !window.__duovaCompanion || e.button !== 0 ||
                e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || !(e.target instanceof Element)) return;
            const c = context(e.target);
            if (!c) return;
            try {
              window.webkit.messageHandlers.duova.postMessage({type:'open',path:c.url.pathname,kind:c.kind});
              e.preventDefault(); e.stopImmediatePropagation();
            } catch (_) { /* Leave the site's action intact when there is no bridge. */ }
          }, true);
          let candidateTimer;
          const suggest = e => {
            if (!e.isTrusted || !(e.target instanceof Element)) return;
            const c = context(e.target);
            clearTimeout(candidateTimer);
            if (!c || !/^\/p\/[A-Za-z0-9_-]+\/$/.test(c.url.pathname)) return;
            candidateTimer = setTimeout(() => {
              if (document.hidden) return;
              try { window.webkit.messageHandlers.duova.postMessage({type:'prefetch',path:c.url.pathname}); } catch (_) {}
            }, 400);
          };
          document.addEventListener('pointerover',suggest,{passive:true});
          document.addEventListener('focusin',suggest,{passive:true});
          document.addEventListener('pointerout',() => clearTimeout(candidateTimer),{passive:true});
        })();
        """#
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
