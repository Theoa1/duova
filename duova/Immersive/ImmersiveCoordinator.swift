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
    private(set) var companionStatus: String? = "Comments appear here when you open a post or Reel. You can also choose Messages or Explore above."
    private(set) var phase: Phase = .loading
    private(set) var primaryRoute = "/"
    var navigationNotice: String?
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
    @ObservationIgnored private var pendingCompanionRestore: ImmersiveCheckpoint?
    @ObservationIgnored private var restoreTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    @ObservationIgnored private var captureGeneration = 0
    @ObservationIgnored private var restoreTokens: [ObjectIdentifier: UUID] = [:]
    @ObservationIgnored private var loginInterrupted: Set<ObjectIdentifier> = []
    @ObservationIgnored private var lastCheckpoint: ImmersiveCheckpoint?
    @ObservationIgnored private let preloader = SocialPreloadCoordinator()
    @ObservationIgnored private var networkAllowsPreload = false
    @ObservationIgnored private var sceneActive = false
    @ObservationIgnored private var companionPresentationTask: Task<Void, Never>?
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
        companionPresentationTask?.cancel()
        for task in restoreTasks.values { task.cancel() }
        for observer in lifecycleObservers { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: Launch and restore

    /// Loads the last safe route (or the site's home) once. Later calls are no-ops.
    func start() {
        guard !started else { return }
        started = true
        startNetworkMonitor()

        let checkpoint = checkpoints.load(accountID: accountID, service: service)
        var target = adapter.homeURL
        if opening == .resumeLast, let checkpoint, checkpoint.adapterVersion <= adapter.version,
           let url = adapter.url(forCheckpointRoute: checkpoint.primaryRoute) {
            target = url
            pendingRestore = checkpoint
            lastCheckpoint = checkpoint
            pendingCompanionRestore = checkpoint
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
        guard adapter.isSiteHost(url), adapter.acceptsCompanion(kind, url: url) else { return }
        preloader.cancel()
        if remember { pendingCompanionRestore = nil }
        let pane: SocialPane
        if let companion {
            pane = companion
        } else {
            pane = SocialPane(role: .companion, adapter: adapter, dataStore: dataStore)
            pane.delegate = self
            observeScroll(of: pane)
            companion = pane
        }
        let kind = kind == .post ? CompanionKind.comments : kind
        companionKind = kind
        companionPresentationTask?.cancel()
        if pane.lastError != nil || pane.webView.url?.path != url.path || pane.webView.url?.host() != url.host() {
            companionStatus = "Preparing " + kind.rawValue + "…"
            pane.load(url)
        }
        if !pane.webView.isLoading && remember { presentCompanionContext(pane) }
        if remember { scheduleCheckpoint() }
    }

    private func presentCompanionContext(_ pane: SocialPane) {
        guard let companionKind, pane.webView.window != nil, !pane.webView.isHidden else { return }
        companionPresentationTask?.cancel()
        let generation = pane.navigationGeneration
        companionPresentationTask = Task { [weak self, weak pane] in
            guard let self, let pane else { return }
            let interaction = await pane.evaluate("window.__duovaState ? window.__duovaState.interaction() : 0") as? Int
            for _ in 0..<8 {
                guard !Task.isCancelled, pane.navigationGeneration == generation,
                      self.adapter.isSiteHost(pane.webView.url) else { return }
                let current = await pane.evaluate("window.__duovaState ? window.__duovaState.interaction() : 0") as? Int
                guard current == interaction else { return }
                if await pane.evaluate(self.adapter.companionPresentationScript(for: companionKind)) as? Bool == true { return }
                try? await Task.sleep(for: .milliseconds(400))
            }
            self.companionStatus = "Instagram hasn’t made this component available yet. Choose Reload from the menu to try again."
        }
    }

    /// Native navigation changes only the primary page.
    func openOwnProfile() {
        Task { [weak self] in
            guard let self, adapter.isSiteHost(primary.webView.url) else { return }
            let generation = primary.navigationGeneration
            let script = """
            (() => {
              for (const a of document.querySelectorAll('[data-duova-native-navigation] a[href]')) {
                const label = ((a.getAttribute('aria-label') || '') + ' ' + a.textContent).toLowerCase();
                const image = a.querySelector('img');
                if (!/profile|perfil|profil/.test(label) && !image) continue;
                const u = new URL(a.href, location.href);
                if (u.origin === location.origin) return u.pathname;
              }
              return null;
            })()
            """
            let path = await primary.evaluate(script) as? String
            guard generation == primary.navigationGeneration else { return }
            if let path, let url = adapter.url(forCheckpointRoute: path),
               adapter.companionKind(for: url, from: nil) == .profile {
                navigatePrimary(path)
            } else {
                navigationNotice = "Instagram hasn’t exposed a profile link on this page yet."
            }
        }
    }

    func navigatePrimary(_ path: String) {
        guard let url = adapter.url(forCheckpointRoute: path) else { return }
        pendingRestore = nil
        restoreTasks[ObjectIdentifier(primary)]?.cancel()
        primary.load(url)
    }

    func selectCompanion(_ kind: CompanionKind) {
        switch kind {
        case .messages, .explore:
            let path = kind == .messages ? "/direct/inbox/" : "/explore/"
            if let url = adapter.url(forCheckpointRoute: path) { openInCompanion(url, kind: kind) }
        case .comments, .post:
            Task { [weak self] in
                guard let self else { return }
                let generation = primary.navigationGeneration
                let anchor = await primary.evaluate(adapter.anchorScript) as? String
                guard generation == primary.navigationGeneration, companionAvailable else { return }
                let url = anchor.flatMap { adapter.url(forCheckpointRoute: $0) } ?? primary.webView.url
                if let url, adapter.acceptsCompanion(.comments, url: url) {
                    openInCompanion(url, kind: .comments)
                } else {
                    navigationNotice = "Open a post or Reel, then choose Comments. You can also tap its comment button."
                }
            }
        default: break
        }
    }

    func retryCompanion() {
        guard let companion else { return }
        companionStatus = "Reloading…"
        companion.retry()
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

    private func captureState(of pane: SocialPane) async -> SocialPageState? {
        guard let url = pane.webView.url, adapter.isSiteHost(url),
              let route = adapter.checkpointRoute(for: url), route == url.path,
              let value = await pane.evaluate("window.__duovaState ? window.__duovaState.capture() : null"),
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value), data.count < 16_384,
              var state = try? JSONDecoder().decode(SocialPageState.self, from: data),
              state.route == route, state.x.isFinite, state.y.isFinite else { return nil }
        if let anchor = state.anchor,
           adapter.url(forCheckpointRoute: anchor) == nil { state.anchor = nil; state.anchorOffset = nil }
        state.media = state.media.filter {
            $0.seconds.isFinite && $0.seconds >= 0 && $0.seconds <= 86_400 &&
            ($0.anchor.map { adapter.url(forCheckpointRoute: $0) != nil } ?? true)
        }
        return state
    }

    func captureCheckpoint() async {
        // Never overwrite a good checkpoint with a not-yet-restored page at offset zero.
        guard pendingRestore == nil, restoreTasks.isEmpty,
              let primaryURL = primary.webView.url, let route = adapter.checkpointRoute(for: primaryURL),
              !primary.webView.isLoading else { return }
        captureGeneration += 1
        let generation = captureGeneration
        let primaryNavigation = primary.navigationGeneration
        let companionNavigation = companion?.navigationGeneration
        let primaryState = await captureState(of: primary)
        let companionState: SocialPageState?
        if let companion { companionState = await captureState(of: companion) } else { companionState = nil }
        guard generation == captureGeneration, primaryNavigation == primary.navigationGeneration,
              companionNavigation == companion?.navigationGeneration,
              primary.webView.url == primaryURL else { return }
        let companionRoute = companion?.webView.url.flatMap { adapter.checkpointRoute(for: $0) }
        var checkpoint = ImmersiveCheckpoint(
            adapterVersion: adapter.version, accountID: accountID, service: service, primaryRoute: route,
            companionRoute: companionRoute, companionKind: companionRoute == nil ? nil : companionKind,
            splitRatio: splitRatio, primaryScrollY: primary.webView.scrollView.contentOffset.y,
            companionScrollY: companion?.webView.scrollView.contentOffset.y ?? 0, anchor: primaryState?.anchor,
            posture: currentPosture, capturedAt: .now)
        checkpoint.primaryState = primaryState
        checkpoint.companionState = companionState
        if let pendingCompanionRestore {
            checkpoint.companionRoute = pendingCompanionRestore.companionRoute
            checkpoint.companionKind = pendingCompanionRestore.companionKind
            checkpoint.companionScrollY = pendingCompanionRestore.companionScrollY
            checkpoint.companionState = pendingCompanionRestore.companionState
        }
        lastCheckpoint = checkpoint
        checkpoints.save(checkpoint)
    }

    private func beginRestore(for pane: SocialPane) {
        let id = ObjectIdentifier(pane)
        guard restoreTasks[id] == nil, !pane.webView.isLoading,
              pane.webView.window != nil, !pane.webView.isHidden,
              pane.webView.bounds.width > 0, pane.webView.bounds.height > 0 else { return }
        let checkpoint = pane === primary ? pendingRestore : pendingCompanionRestore
        guard let checkpoint else { return }
        let token = UUID()
        restoreTokens[id] = token
        restoreTasks[id] = Task { [weak self, weak pane] in
            guard let self, let pane else { return }
            await self.finishRestore(checkpoint, for: pane)
            if self.restoreTokens[id] == token {
                self.restoreTasks[id] = nil
                self.restoreTokens[id] = nil
            }
        }
    }

    private func finishRestore(_ checkpoint: ImmersiveCheckpoint, for pane: SocialPane) async {
        let route = pane === primary ? checkpoint.primaryRoute : checkpoint.companionRoute
        guard let route else { return }
        let generation = pane.navigationGeneration
        let id = ObjectIdentifier(pane)
        guard let url = pane.webView.url, adapter.isSiteHost(url), url.path == route else {
            if pane.webView.url.map(isLoginRoute) == true {
                loginInterrupted.insert(id)
                record(.siteRequiresLogin)
            } else if loginInterrupted.remove(id) != nil,
                      let target = adapter.url(forCheckpointRoute: route) {
                // One safe navigation after the site's own login. Never replay inputs.
                pane.load(target)
            } else {
                if pane === primary { pendingRestore = nil } else { pendingCompanionRestore = nil }
                record(.partial)
            }
            return
        }
        loginInterrupted.remove(id)
        let state = (pane === primary ? checkpoint.primaryState : checkpoint.companionState) ??
            SocialPageState(route: route, x: 0,
                y: Double(pane === primary ? checkpoint.primaryScrollY : checkpoint.companionScrollY),
                anchor: pane === primary ? checkpoint.anchor : nil, anchorOffset: 0, scrollers: [], media: [])
        var restored = false
        var interaction: Int?
        for _ in 0..<12 {
            guard !Task.isCancelled, generation == pane.navigationGeneration,
                  pane.webView.url?.path == route, adapter.isSiteHost(pane.webView.url) else { return }
            if interaction == nil {
                interaction = await pane.evaluate("window.__duovaState ? window.__duovaState.interaction() : null") as? Int
            }
            if let interaction, let script = SocialPageScripts.restore(state, interaction: interaction),
               let result = await pane.evaluate(script) as? [String: Any] {
                if result["interrupted"] as? Bool == true { break }
                if result["done"] as? Bool == true { restored = true; break }
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        guard !Task.isCancelled, generation == pane.navigationGeneration else { return }
        if pane === primary { pendingRestore = nil } else { pendingCompanionRestore = nil }
        record(restored ? .restored : .partial)
    }

    func paneDidBecomeVisible(_ pane: SocialPane) {
        beginRestore(for: pane)
    }

    func setSceneActive(_ active: Bool) {
        sceneActive = active
        primary.setContentVisible(active)
        companion?.setContentVisible(active && companionAvailable && companionKind != .comments)
        preloader.enabled = active && networkAllowsPreload
        if !active { saveCheckpointNow() }
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
        for name in [UIApplication.didReceiveMemoryWarningNotification, Notification.Name.NSProcessInfoPowerStateDidChange,
                     ProcessInfo.thermalStateDidChangeNotification] {
            lifecycleObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.preloader.cancel()
                    self?.saveCheckpointNow()
                }
            })
        }
    }

    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let permitsPreload = online && !path.isConstrained && !path.isExpensive
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOnline = self.isOnline
                self.isOnline = online
                self.networkAllowsPreload = permitsPreload
                self.preloader.enabled = permitsPreload && self.sceneActive
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
    private func updateNavigationState(_ pane: SocialPane) {
        guard let url = pane.webView.url, adapter.isSiteHost(url) else { return }
        if pane === primary {
            let path = adapter.checkpointRoute(for: url) ?? "/"
            if primaryRoute != path {
                primaryRoute = path
                if companionAvailable, adapter.acceptsCompanion(.comments, url: url) {
                    openInCompanion(url, kind: .comments)
                }
            }
        } else if let kind = adapter.companionKind(for: url, from: nil) {
            if !(kind == .post && companionKind == .comments), companionKind != kind { companionKind = kind }
        }
    }

    func paneRequestsCurrentComments(_ pane: SocialPane) {
        guard pane === primary, companionAvailable else { return }
        selectCompanion(.comments)
    }

    func pane(_ pane: SocialPane, componentReady: Bool) {
        guard pane !== primary else { return }
        companionStatus = componentReady ? nil : "Preparing " + (companionKind?.rawValue ?? "content") + "…"
    }

    func paneStateDidChange(_ pane: SocialPane) {
        updateNavigationState(pane)
        if pane === primary && pendingRestore != nil || pane !== primary && pendingCompanionRestore != nil {
            if restoreTasks[ObjectIdentifier(pane)] == nil { beginRestore(for: pane) }
        }
        scheduleCheckpoint(after: .milliseconds(300))
    }

    func pane(_ pane: SocialPane, suggestsPrefetch url: URL) {
        guard phase == .ready, pendingRestore == nil, restoreTasks.isEmpty else { return }
        preloader.suggest(url, in: pane)
    }

    func pane(_ pane: SocialPane, didCommit url: URL?) {
        updateNavigationState(pane)
        preloader.cancel()
        if pane === primary {
            phase = .ready
        }
    }

    func pane(_ pane: SocialPane, didFinish url: URL?) {
        if pane === primary {
            phase = .ready
            pane.setCompanionAvailable(companionAvailable)
        }
        if pane !== primary && pendingCompanionRestore == nil { presentCompanionContext(pane) }
        beginRestore(for: pane)
        scheduleCheckpoint(after: .milliseconds(400))
    }

    func pane(_ pane: SocialPane, didFail error: Error) {
        guard pane === primary else {
            // Keep the anchored feed usable. A failed context can be retried by
            // selecting its original website control again.
            companionStatus = isOnline ? "This component couldn’t be loaded. Choose Reload to try again." : "Offline. Choose Reload when you’re connected."
            record(isOnline ? .unavailable : .offline)
            return
        }
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
        preloader.cancel()
        restoreTasks[ObjectIdentifier(pane)]?.cancel()
        let checkpoint = lastCheckpoint ?? checkpoints.load(accountID: accountID, service: service)
        if pane === primary {
            phase = .loading
            pendingRestore = checkpoint
        } else { pendingCompanionRestore = checkpoint }
        let route = pane === primary ? checkpoint?.primaryRoute : checkpoint?.companionRoute
        if let route, let url = adapter.url(forCheckpointRoute: route) { pane.load(url) }
        else { pane.retry() }
    }

    func pane(_ pane: SocialPane, requestsCompanion url: URL, kind: CompanionKind) {
        guard companionAvailable else { return }
        if kind == .post {
            navigatePrimary(url.path)
            openInCompanion(url, kind: .comments)
        } else {
            openInCompanion(url, kind: kind)
        }
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
