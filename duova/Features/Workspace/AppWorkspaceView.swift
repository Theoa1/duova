import SwiftUI
import WebKit

/// An app opened inside Duova: its website, already signed in when Duova holds
/// its session. Full screen, with only a small floating X back to Duova.
struct AppWorkspaceView: View {
    @Environment(AppSignInCenter.self) private var center
    @Environment(\.duovaTheme) private var theme
    let service: Service
    let url: URL
    let close: () -> Void

    @State private var page: AppWorkspacePage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let page {
                WebViewHost(webView: page.webView)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .padding(.leading, 12)
            .padding(.top, 6)
            .accessibilityLabel("Close \(service.name)")
        }
        .background { DuovaBackdrop() }
        .task {
            let dataStore = await center.prepareLaunch(service.id)
            page = AppWorkspacePage(url: url, dataStore: dataStore)
        }
        .onDisappear {
            let id = service.id
            Task { await center.endLaunch(id) }
        }
    }
}

/// The web view for an opened app, sharing that app's own cookie jar.
final class AppWorkspacePage: NSObject, WKNavigationDelegate {
    let webView: WKWebView

    init(url: URL, dataStore: WKWebsiteDataStore) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.load(URLRequest(url: url))
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        // Stay on the web: no jumps into other apps or custom schemes.
        let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
        decisionHandler(["https", "about", "blob", "data"].contains(scheme) ? .allow : .cancel)
    }
}
