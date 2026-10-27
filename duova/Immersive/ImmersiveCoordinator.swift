import Foundation
import Network
import UIKit
import WebKit

/// How the last restore went; recorded locally only, for diagnostics.
enum RestoreOutcome: String {
    case restored, partial, siteRequiresLogin, offline, unavailable
}

/// Runs one launched service for one account: the live web surfaces, the
/// checkpoint that remembers where the person is, and recovery when the site
/// or network fails. Created once per launch and kept for as long as the
/// launch is committed, across lock, background and layout changes.
@Observable
@MainActor
final class ImmersiveCoordinator {
    enum Phase: Equatable {
        /// Nothing committed on screen yet (cold start or recovering).
        case loading
        /// The site is showing; everything after this is the site's own.
        case ready
        /// No connection; retrying when one returns.
        case offline
        /// The site couldn't be loaded for another reason.
        case unavailable
    }

    let accountID: UUID
    let service: ServiceID
    let adapter: any SocialAdapter
    let primary: SocialPane
    private(set) var companion: SocialPane?
    private(set) var companionKind: CompanionKind?
    private(set) var phase: Phase = .loading
    /// Something to show in the companion pane when geometry allows.
    var companionWanted: Bool { companion != nil && companionKind != nil }
    private(set) var lastOutcome: RestoreOutcome?

    /// Layout preferences in effect for this service.
    let expandedLayout: ExpandedLayout
    private(set) var splitRatio: PanelRatio
    let opening: OpeningBehavior
    /// Posture the compositor is currently showing, remembered in the checkpoint.
    var currentPosture: SocialPosture = .closedPortrait {
        didSet { if oldValue != currentPosture { scheduleCheckpoint() } }
    }

    @ObservationIgnored private let dataStore: WKWebsiteDataStore
    @ObservationIgnored private let checkpoints: ImmersiveCheckpointStore
    @ObservationIgnored private var pendingRestore: ImmersiveCheckpoint?
    @ObservationIgnored private var checkpointTask: Task<Void, Never>?
    @ObservationIgnored private var scrollObservers: [NSKeyValueObservation] = []
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var isOnline = true
    @ObservationIgnored private var started = false
    @ObservationIgnored private var lifecycleObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var companionAvailableStorage = false

    init(accountID: UUID, service: ServiceID, adapter: any SocialAdapter, preferences: ServicePreferences,
         store: SecureStore? = nil) {
        let store = store ?? .shared
        self.accountID = accountID
        self.service = service
        self.adapter = adapter
        let overrides = preferences.overrides(for: service)
        expandedLayout = overrides.expandedLayout ?? preferences.defaults.expandedLayout
        splitRatio = overrides.panelRatio ?? preferences.defaults.panelRatio
        opening = overrides.opening ?? preferences.defaults.opening
        checkpoints = ImmersiveCheckpointStore(store: store)
        dataStore = ServiceSessionRegistry.dataStore(accountID: accountID, service: service, store: store)
        primary = SocialPane(role: .primary, adapter: adapter, dataStore: dataStore)
        primary.delegate = self
        observeScroll(of: primary)
        observeLifecycle()
    }

    deinit {
        checkpointTask?.cancel()
        pathMonitor?.cancel()
    }

    // MARK: Launch and restore

    /// Loads the last safe route (or the site's home) once. Later calls are no-ops.
    func start() {
        guard !started else { return }
        started = true
        startNetworkMonitor()

        let checkpoint = checkpoints.load(accountID: accountID, service: service)
        var target = adapter.homeURL
        if opening == .resumeLast, let checkpoint, checkpoint.adapterVersion == adapter.version,
           let url = adapter.url(forCheckpointRoute: checkpoint.primaryRoute) {
            target = url
            pendingRestore = checkpoint
            if let saved = checkpoint.splitRatio { splitRatio = saved }
            if let route = checkpoint.companionRoute, let kind = checkpoint.companionKind,
               let companionURL = adapter.url(forCheckpointRoute: route) {
                openInCompanion(companionURL, kind: kind, remember: false)
            }
        }
        primary.load(target)
    }

    /// Retry from the fallback surface: same instances, same route.
    func retry() {
        phase = .loading
        primary.retry()
        companion?.retry()
    }

    /// The site asked (through its own links) for context in the second pane.
    /// The companion surface is created on first use and then reused.
    func openInCompanion(_ url: URL, kind: CompanionKind, remember: Bool = true) {
        guard adapter.allowsMainFrame(url) else { return }
        let pane: SocialPane
        if let companion {
            pane = companion
        } else {
            pane = SocialPane(role: .companion, adapter: adapter, dataStore: dataStore)
            pane.delegate = self
            observeScroll(of: pane)
            companion = pane
        }
        companionKind = kind
        pane.load(url)
        if remember { scheduleCheckpoint() }
    }

    func updateSplitRatio(_ ratio: PanelRatio) {
        guard ratio != splitRatio else { return }
        splitRatio = ratio
        scheduleCheckpoint()
    }

    // MARK: Checkpoints

    /// Writes the checkpoint now (before background, lock, or leaving the scene).
    func saveCheckpointNow() {
        checkpointTask?.cancel()
        checkpointTask = nil
        Task { await captureCheckpoint() }
    }

    private func scheduleCheckpoint(after delay: Duration = .seconds(1.5)) {
        checkpointTask?.cancel()
        checkpointTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.captureCheckpoint()
        }
    }

    private func captureCheckpoint() async {
        guard let primaryURL = primary.webView.url, let route = adapter.checkpointRoute(for: primaryURL) else { return }
        var companionRoute: String?
        if let companion, let url = companion.webView.url {
            companionRoute = adapter.checkpointRoute(for: url)
        }
        let anchor = await currentAnchor()
        let checkpoint = ImmersiveCheckpoint(
            adapterVersion: adapter.version, accountID: accountID, service: service, primaryRoute: route,
            companionRoute: companionRoute, companionKind: companionRoute == nil ? nil : companionKind,
            splitRatio: splitRatio, primaryScrollY: primary.webView.scrollView.contentOffset.y,
            companionScrollY: companion?.webView.scrollView.contentOffset.y ?? 0, anchor: anchor,
            posture: currentPosture, capturedAt: .now)
        checkpoints.save(checkpoint)
    }

    private func currentAnchor() async -> String? {
        guard adapter.isSiteHost(primary.webView.url), !adapter.anchorScript.isEmpty, adapter.anchorScript != "null"
        else { return nil }
        let result = await primary.evaluate(adapter.anchorScript)
        guard let path = result as? String, let url = SocialRoutes.url(path: path, on: adapter.homeURL),
              adapter.checkpointRoute(for: url) != nil
        else { return nil }
        return path
    }

    /// Bounded, best-effort position restore after the page is actually ready,
    /// only when the site landed on the route that was remembered.
    private func finishRestoreIfNeeded(for pane: SocialPane, url: URL?) async {
        guard let checkpoint = pendingRestore, pane === primary else { return }
        pendingRestore = nil
        guard let url, adapter.isSiteHost(url) else {
            record(.unavailable)
            return
        }
        guard adapter.checkpointRoute(for: url) == checkpoint.primaryRoute else {
            // The site sent us elsewhere (its sign-in, or a redirect). Leave it be.
            record(isLoginRoute(url) ? .siteRequiresLogin : .partial)
            return
        }
        // Give the site a moment to lay out, then try the anchor, then the offset.
        try? await Task.sleep(for: .milliseconds(600))
        var anchored = false
        if let anchor = checkpoint.anchor {
            let result = await pane.evaluate(adapter.scrollToAnchorScript(anchor))
            anchored = (result as? Bool) ?? false
        }
        if !anchored, checkpoint.primaryScrollY > 0 {
            let scrollView = pane.webView.scrollView
            let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            scrollView.setContentOffset(CGPoint(x: 0, y: min(checkpoint.primaryScrollY, maxY)), animated: false)
            anchored = maxY > 0
        }
        record(anchored ? .restored : .partial)
    }

    private func isLoginRoute(_ url: URL) -> Bool {
        let first = url.path(percentEncoded: false).split(separator: "/", omittingEmptySubsequences: true).first.map(String.init)
        return first == "accounts" || first == "challenge" || adapter.authHosts.contains(url.host()?.lowercased() ?? "")
    }

    private func record(_ outcome: RestoreOutcome) {
        lastOutcome = outcome
    }

    // MARK: Observation

    private func observeScroll(of pane: SocialPane) {
        let observation = pane.webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.scheduleCheckpoint(after: .seconds(2)) }
        }
        scrollObservers.append(observation)
    }

    private func observeLifecycle() {
        let center = NotificationCenter.default
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willResignActiveNotification,
                     UIApplication.willTerminateNotification] {
            lifecycleObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.saveCheckpointNow() }
            })
        }
    }

    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOnline = self.isOnline
                self.isOnline = online
                if online, !wasOnline, self.phase == .offline {
                    self.retry()
                } else if !online, self.phase == .loading {
                    self.phase = .offline
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "duova.immersive.network"))
        pathMonitor = monitor
    }
}

// MARK: - Pane events

extension ImmersiveCoordinator: SocialPaneDelegate {
    func pane(_ pane: SocialPane, didCommit url: URL?) {
        if pane === primary {
            phase = .ready
        }
    }

    func pane(_ pane: SocialPane, didFinish url: URL?) {
        if pane === primary {
            phase = .ready
            pane.setCompanionAvailable(companionAvailable)
            Task { await finishRestoreIfNeeded(for: pane, url: url) }
        }
        scheduleCheckpoint(after: .milliseconds(400))
    }

    func pane(_ pane: SocialPane, didFail error: Error) {
        guard pane === primary, phase != .ready || primary.webView.url == nil else { return }
        let nsError = error as NSError
        let offlineCodes = [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
                            NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed]
        if nsError.domain == NSURLErrorDomain, offlineCodes.contains(nsError.code) || !isOnline {
            phase = .offline
            record(.offline)
        } else {
            phase = .unavailable
            record(.unavailable)
        }
    }

    func paneProcessDidTerminate(_ pane: SocialPane) {
        // Same instance, same route; the checkpoint already remembers the position.
        if pane === primary {
            phase = .loading
            pendingRestore = checkpoints.load(accountID: accountID, service: service)
        }
        pane.retry()
    }

    func pane(_ pane: SocialPane, requestsCompanion url: URL, kind: CompanionKind) {
        guard companionAvailable else { return }
        openInCompanion(url, kind: kind)
    }

    /// Set by the compositor from current geometry; tells the primary whether
    /// taps on context links should go to the second pane.
    var companionAvailable: Bool {
        get { companionAvailableStorage }
        set {
            guard companionAvailableStorage != newValue else { return }
            companionAvailableStorage = newValue
            primary.setCompanionAvailable(newValue)
        }
    }
}
