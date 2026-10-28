import UIKit
import WebKit

/// What a pane tells its coordinator.
@MainActor
protocol SocialPaneDelegate: AnyObject {
    func pane(_ pane: SocialPane, didCommit url: URL?)
    func pane(_ pane: SocialPane, didFinish url: URL?)
    func pane(_ pane: SocialPane, didFail error: Error)
    func paneProcessDidTerminate(_ pane: SocialPane)
    /// The site asked to open a route the adapter classifies as companion content.
    func paneRequestsCurrentComments(_ pane: SocialPane)
    func paneStateDidChange(_ pane: SocialPane)
    func pane(_ pane: SocialPane, componentReady: Bool)
    func pane(_ pane: SocialPane, suggestsPrefetch url: URL)
    func pane(_ pane: SocialPane, requestsCompanion url: URL, kind: CompanionKind)
}

/// One web surface (primary or companion) with the site's own navigation and
/// Duova's exact-host policy. The web view is created once and never
/// re-created for a layout change.
@MainActor
final class SocialPane: NSObject {
    enum Role { case primary, companion }

    let role: Role
    let adapter: any SocialAdapter
    let webView: WKWebView
    weak var delegate: SocialPaneDelegate?
    /// Pane width the content mode is chosen for; set by the compositor.
    var layoutWidth: CGFloat = 0 {
        didSet { if layoutWidth != oldValue { updatePresentation() } }
    }
    private(set) var navigationGeneration = 0
    private var companionEnabled = false
    private var contentVisible = true

    func setContentVisible(_ visible: Bool) {
        guard contentVisible != visible else { return }
        contentVisible = visible
        webView.setAllMediaPlaybackSuspended(!visible, completionHandler: nil)
    }

    func updatePresentation() {
        guard adapter.isSiteHost(webView.url) else { return }
        let roleName = role == .primary ? "primary" : "companion"
        // Idempotent writes avoid feeding mutations back into the site's renderer.
        let script = "if (document.documentElement && document.documentElement.dataset.duovaPane !== '\(roleName)') document.documentElement.dataset.duovaPane = '\(roleName)'; true"
        webView.evaluateJavaScript(script, in: nil, in: SocialWebViewFactory.contentWorld) { _ in }
    }

    /// A site that returned an error for the main frame.
    private(set) var lastError: Error?

    init(role: Role, adapter: any SocialAdapter, dataStore: WKWebsiteDataStore) {
        self.role = role
        self.adapter = adapter
        let bridge = MessageBridge()
        webView = SocialWebViewFactory.make(
            adapter: adapter, dataStore: dataStore, messageHandler: bridge, injectsScripts: role == .primary)
        super.init()
        bridge.pane = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func load(_ url: URL) {
        lastError = nil
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
    }

    /// Reload after a failure or a content-process crash, on the same instance.
    func retry() {
        lastError = nil
        if webView.url != nil {
            webView.reload()
        } else {
            load(adapter.homeURL)
        }
    }

    /// Lets the injected script know whether taps on companion links should be
    /// forwarded (two panes) or left to the site (one pane).
    func setCompanionAvailable(_ available: Bool) {
        guard role == .primary else { return }
        companionEnabled = available
        webView.evaluateJavaScript(
            "window.__duovaCompanion = \(available ? "true" : "false"); true",
            in: nil, in: SocialWebViewFactory.contentWorld) { _ in }
    }

    /// Runs `script` in Duova's content world and returns its result, or nil.
    func evaluate(_ script: String) async -> Any? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script, in: nil, in: SocialWebViewFactory.contentWorld) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure: continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: Messages from the injected script

    fileprivate func receive(_ body: Any) {
        guard let dictionary = body as? [String: Any], let type = dictionary["type"] as? String else { return }
        switch type {
        case "open":
            guard let path = dictionary["path"] as? String, let kindName = dictionary["kind"] as? String,
                  let kind = CompanionKind(rawValue: kindName), let url = SocialRoutes.url(path: path, on: adapter.homeURL),
                  role == .primary, companionEnabled, adapter.acceptsCompanion(kind, url: url)
            else { return }
            delegate?.pane(self, requestsCompanion: url, kind: kind)
        case "currentComments":
            guard role == .primary, companionEnabled else { return }
            delegate?.paneRequestsCurrentComments(self)
        case "component":
            guard role == .companion, let status = dictionary["status"] as? String,
                  status == "ready" || status == "waiting" else { return }
            delegate?.pane(self, componentReady: status == "ready")
        case "focusPost":
            guard role == .companion, let path = dictionary["path"] as? String,
                  let url = SocialRoutes.url(path: path, on: adapter.homeURL),
                  adapter.acceptsCompanion(.comments, url: url) else { return }
            delegate?.pane(self, requestsCompanion: url, kind: .post)
        case "state":
            delegate?.paneStateDidChange(self)
        case "prefetch":
            guard role == .primary, let path = dictionary["path"] as? String,
                  let url = SocialRoutes.url(path: path, on: adapter.homeURL), adapter.permitsPrefetch(url) else { return }
            delegate?.pane(self, suggestsPrefetch: url)
        default:
            break
        }
    }

    /// Message handler that doesn't retain the pane (WebKit holds handlers strongly).
    private final class MessageBridge: NSObject, WKScriptMessageHandler {
        weak var pane: SocialPane?
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == SocialWebViewFactory.messageHandlerName, message.frameInfo.isMainFrame,
                  let pane, pane.adapter.isSiteHost(pane.webView.url),
                  message.frameInfo.securityOrigin.protocol == "https",
                  pane.adapter.siteHosts.contains(message.frameInfo.securityOrigin.host.lowercased()) else { return }
            pane.receive(message.body)
        }
    }
}

// MARK: - Navigation policy

extension SocialPane: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction, preferences: WKWebpagePreferences
    ) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        if role == .companion && action.navigationType == .backForward { return (.cancel, preferences) }
        guard let url = action.request.url else { return (.cancel, preferences) }
        let scheme = url.scheme?.lowercased() ?? ""

        // Subframes are the site's business; only the main frame is policed.
        guard action.targetFrame?.isMainFrame ?? true else {
            return (scheme == "https" || scheme == "about" || scheme == "blob" ? .allow : .cancel, preferences)
        }

        if scheme == "about" || scheme == "blob" {
            return (.allow, preferences)
        }
        guard scheme == "https" else {
            // tel:, mailto:, custom app schemes: not inside the service.
            return (.cancel, preferences)
        }
        guard adapter.allowsMainFrame(url) else {
            // Another website: hand to the system browser, stay on the service.
            if action.navigationType == .linkActivated || action.navigationType == .other {
                await UIApplication.shared.open(url)
            }
            return (.cancel, preferences)
        }

        // Every route (including login, messages and profiles) uses the phone
        // presentation in narrow panes. Resize alone never reloads a live page.
        preferences.preferredContentMode = adapter.prefersMobileContent || layoutWidth < adapter.desktopMinimumWidth
            ? .mobile : .desktop
        preferences.allowsContentJavaScript = true
        return (.allow, preferences)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        navigationGeneration += 1
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updatePresentation()
        setCompanionAvailable(companionEnabled)
        delegate?.pane(self, didCommit: webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updatePresentation()
        setCompanionAvailable(companionEnabled)
        delegate?.pane(self, didFinish: webView.url)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        delegate?.paneProcessDidTerminate(self)
    }

    private func report(_ error: Error) {
        let nsError = error as NSError
        // A navigation the site itself replaced isn't a failure.
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 { return }  // frame load interrupted
        lastError = error
        delegate?.pane(self, didFail: error)
    }
}

// MARK: - UI delegate

extension SocialPane: WKUIDelegate {
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // target="_blank": same pane, same policy. No pop-up windows.
        if let url = action.request.url {
            if adapter.allowsMainFrame(url) {
                webView.load(action.request)
            } else if url.scheme?.lowercased() == "https" {
                UIApplication.shared.open(url)
            }
        }
        return nil
    }

    func webView(
        _ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
        initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType
    ) async -> WKPermissionDecision {
        // Camera and microphone: only for the service itself, and only with
        // the system's own prompt.
        adapter.siteHosts.contains(origin.host.lowercased()) ? .prompt : .deny
    }

    func webView(
        _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo
    ) async {
        await presentAlert(title: frame.securityOrigin.host, message: message, cancel: nil)
    }

    func webView(
        _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo
    ) async -> Bool {
        await presentAlert(title: frame.securityOrigin.host, message: message, cancel: String(localized: "Cancel"))
    }

    func webView(
        _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
        initiatedByFrame frame: WKFrameInfo
    ) async -> String? {
        guard let presenter = webView.window?.rootViewController?.topMost else { return nil }
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: frame.securityOrigin.host, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in
                continuation.resume(returning: nil)
            })
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { _ in
                continuation.resume(returning: alert.textFields?.first?.text ?? "")
            })
            presenter.present(alert, animated: true)
        }
    }

    @discardableResult
    private func presentAlert(title: String, message: String, cancel: String?) async -> Bool {
        guard let presenter = webView.window?.rootViewController?.topMost else { return false }
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            if let cancel {
                alert.addAction(UIAlertAction(title: cancel, style: .cancel) { _ in continuation.resume(returning: false) })
            }
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { _ in
                continuation.resume(returning: true)
            })
            presenter.present(alert, animated: true)
        }
    }
}

private extension UIViewController {
    var topMost: UIViewController {
        presentedViewController?.topMost ?? self
    }
}
