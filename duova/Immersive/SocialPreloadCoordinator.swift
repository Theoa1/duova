import Foundation
import WebKit

/// P0/P1 always belong to the visible panes. P2 warms at most one reviewed GET
/// in their existing WebKit cache, never a third executing page or hidden video.
/// P3 retains the two live panes; P4 uses their persistent store/checkpoint.
@MainActor
final class SocialPreloadCoordinator {
    struct Budget {
        static let maximumLivePanes = 2
        static let responseBytes = 256 * 1024
        static let sessionBytes = 4 * 1024 * 1024
        static let cooldown: TimeInterval = 30
        static let requestsPerSession = 16
    }

    private(set) var reservedBytes = 0
    private(set) var requestCount = 0
    private var lastRequest = Date.distantPast
    private var attempted: Set<String> = []
    private var pending: Task<Void, Never>?
    private var requestToken = UUID()
    private weak var pane: SocialPane?
    var enabled = false {
        didSet { if !enabled { cancel() } }
    }

    func suggest(_ url: URL, in pane: SocialPane) {
        guard enabled, pending == nil, pane.adapter.permitsPrefetch(url),
              pane.adapter.isSiteHost(pane.webView.url),
              pane.webView.url?.host() == url.host(),
              !pane.webView.isLoading,
              !ProcessInfo.processInfo.isLowPowerModeEnabled,
              ProcessInfo.processInfo.thermalState == .nominal,
              Date().timeIntervalSince(lastRequest) >= Budget.cooldown,
              reservedBytes + Budget.responseBytes <= Budget.sessionBytes,
              requestCount < Budget.requestsPerSession, !attempted.contains(url.path)
        else { return }
        self.pane = pane
        attempted.insert(url.path)
        reservedBytes += Budget.responseBytes
        requestCount += 1
        lastRequest = .now
        let generation = pane.navigationGeneration
        let token = UUID()
        requestToken = token
        pending = Task { [weak self, weak pane] in
            guard let self, let pane else { return }
            defer { if self.requestToken == token { self.pending = nil } }
            // A short idle window lets active navigation take priority.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, self.enabled, generation == pane.navigationGeneration else { return }
            guard let data = try? JSONEncoder().encode(url.path),
                  let path = String(data: data, encoding: .utf8) else { return }
            let script = """
            if (!document.hidden && location.protocol === 'https:') {
              const controller = new AbortController();
              window.__duovaPrefetchAbort = controller;
              const timer = setTimeout(() => controller.abort(), 4000);
              try {
                const response = await fetch(\(path), {
                  method:'GET', credentials:'same-origin', cache:'default', redirect:'error',
                  referrerPolicy:'no-referrer', signal:controller.signal
                });
                const type = response.headers.get('content-type') || '';
                const length = Number(response.headers.get('content-length') || 0);
                if (!response.ok || !type.includes('text/html') || length > \(Budget.responseBytes)) {
                  if (response.body) await response.body.cancel();
                } else if (response.body) {
                  const reader = response.body.getReader();
                  let bytes = 0;
                  while (!controller.signal.aborted) {
                    const chunk = await reader.read();
                    if (chunk.done) break;
                    bytes += chunk.value.byteLength;
                    if (bytes >= \(Budget.responseBytes)) { await reader.cancel(); break; }
                  }
                }
              } catch (_) {
              } finally {
                clearTimeout(timer);
                if (window.__duovaPrefetchAbort === controller) window.__duovaPrefetchAbort = null;
              }
            }
            return true;
            """
            // Async JavaScript runs in the existing isolated world. The response is
            // never inserted, parsed, logged, persisted by Duova, or executed.
            _ = try? await pane.webView.callAsyncJavaScript(
                script, arguments: [:], in: nil, contentWorld: SocialWebViewFactory.contentWorld)
        }
    }

    func cancel() {
        requestToken = UUID()
        pending?.cancel()
        pending = nil
        pane?.webView.evaluateJavaScript(
            "if (window.__duovaPrefetchAbort) window.__duovaPrefetchAbort.abort(); true",
            in: nil, in: SocialWebViewFactory.contentWorld) { _ in }
    }
}
