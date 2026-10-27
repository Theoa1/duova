import Foundation
import WebKit

/// Gives each (Duova account, service) pair one stable WebKit website data
/// store, so the site's own sign-in, cookies and local storage persist across
/// launches and are shared by that service's primary and companion panes, and
/// by nothing else. Another account or another service gets a different store.
///
/// The store identifiers live encrypted with the account's other data, so
/// erasing the account can also erase its website data.
enum ServiceSessionRegistry {
    private struct Registry: Codable {
        var stores: [String: UUID] = [:]
    }

    static func dataStore(accountID: UUID, service: ServiceID, store: SecureStore) -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: identifier(accountID: accountID, service: service, store: store))
    }

    /// The stable identifier for the pair, created the first time it's asked for.
    static func identifier(accountID: UUID, service: ServiceID, store: SecureStore) -> UUID {
        var registry = store.load(Registry.self, name: name(accountID)) ?? Registry()
        if let existing = registry.stores[service.rawValue] { return existing }
        let fresh = UUID()
        registry.stores[service.rawValue] = fresh
        try? store.save(registry, name: name(accountID))
        return fresh
    }

    /// Every store identifier the account has, for erasing them.
    static func identifiers(for accountID: UUID, store: SecureStore) -> [UUID] {
        Array((store.load(Registry.self, name: name(accountID)) ?? Registry()).stores.values)
    }

    private static func name(_ id: UUID) -> String { "web-stores-\(id.uuidString)" }
}

/// The one WKWebView configuration for a social surface.
enum SocialWebViewFactory {
    static let messageHandlerName = "duova"
    static let contentWorld = WKContentWorld.world(name: "duova")

    static func make(
        adapter: any SocialAdapter, dataStore: WKWebsiteDataStore, messageHandler: WKScriptMessageHandler?,
        injectsScripts: Bool
    ) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        // Desktop first; narrow panes ask for the mobile site per navigation (SocialNavigationPolicy).
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        if injectsScripts {
            let controller = configuration.userContentController
            if let messageHandler {
                controller.add(messageHandler, contentWorld: contentWorld, name: messageHandlerName)
            }
            if let css = adapter.styleSheet {
                controller.addUserScript(WKUserScript(
                    source: styleInjector(css: css, hosts: adapter.siteHosts, version: adapter.version),
                    injectionTime: .atDocumentStart, forMainFrameOnly: true, in: contentWorld))
            }
            if !adapter.primaryScript.isEmpty {
                controller.addUserScript(WKUserScript(
                    source: adapter.primaryScript, injectionTime: .atDocumentStart, forMainFrameOnly: true,
                    in: contentWorld))
            }
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground
        return webView
    }

    /// Adds the style only on the site's exact hosts, tagged by adapter version.
    private static func styleInjector(css: String, hosts: Set<String>, version: Int) -> String {
        let hostList = hosts.sorted().map { "'\($0)'" }.joined(separator: ",")
        let encoded = (try? JSONEncoder().encode(css)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return """
        (function () {
          if ([\(hostList)].indexOf(location.host) < 0) { return; }
          var id = 'duova-style-v\(version)';
          function add() {
            if (document.getElementById(id)) { return; }
            var s = document.createElement('style');
            s.id = id;
            s.textContent = \(encoded);
            (document.head || document.documentElement).appendChild(s);
          }
          if (document.head) { add(); } else { document.addEventListener('DOMContentLoaded', add, { once: true }); }
        })();
        """
    }
}
