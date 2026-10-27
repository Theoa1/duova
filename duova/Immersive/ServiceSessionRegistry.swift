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
        // Safe phone default until the host supplies actual pane geometry.
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        do {
            let controller = configuration.userContentController
            if let messageHandler {
                controller.add(messageHandler, contentWorld: contentWorld, name: messageHandlerName)
            }
            if let css = adapter.styleSheet {
                controller.addUserScript(WKUserScript(
                    source: styleInjector(css: css, hosts: adapter.siteHosts, version: adapter.version),
                    injectionTime: .atDocumentStart, forMainFrameOnly: true, in: contentWorld))
            }
            let hosts = adapter.siteHosts.sorted().map { "'\($0)'" }.joined(separator: ",")
            controller.addUserScript(WKUserScript(
                source: "if (location.protocol === 'https:' && [\(hosts)].includes(location.host)) { \(SocialPageScripts.runtime) }",
                injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: contentWorld))
            if adapter.service == .instagram && InstagramAdapter.injectionEnabled {
                controller.addUserScript(WKUserScript(source: InstagramAdapter.navigationScript,
                    injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: contentWorld))
            }
            if injectsScripts && !adapter.primaryScript.isEmpty {
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

    /// Install once, with no mutation observer competing with the site's renderer.
    /// Route changes update the gate explicitly from the lightweight state runtime.
    private static func styleInjector(css: String, hosts: Set<String>, version: Int) -> String {
        let hostList = hosts.sorted().map { "'\($0)'" }.joined(separator: ",")
        let encoded = (try? JSONEncoder().encode(css)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return """
        (() => {
          if (location.protocol !== 'https:' || ![\(hostList)].includes(location.host)) return;
          const id = 'duova-style-v\(version)';
          window.__duovaRefreshStyle = () => {
            const root = document.documentElement;
            if (!root) return;
            const blocked = /^\\/(accounts|challenge|oauth|emails|session)(\\/|$)/.test(location.pathname);
            const value = blocked ? '' : '\(version)';
            if (root.getAttribute('data-duova-instagram') !== value)
              root.setAttribute('data-duova-instagram', value);
          };
          function add() {
            if (!document.getElementById(id)) {
              const style = document.createElement('style');
              style.id = id;
              style.textContent = \(encoded);
              (document.head || document.documentElement).appendChild(style);
            }
            window.__duovaRefreshStyle();
          }
          if (document.head) add();
          else document.addEventListener('DOMContentLoaded', add, {once:true});
        })();
        """
    }
}
