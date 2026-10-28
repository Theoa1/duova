import SwiftUI

/// Hosts the launch overlay above the app's first destination.
///
/// The destination is chosen from the persisted (encrypted) session: sign in
/// when there isn't one, the unlock screen when App Lock is on, and the main
/// shell otherwise. It is built immediately underneath the launch overlay, so
/// the hand-off is a simple crossfade and nothing is deferred until the
/// animation ends.
struct RootView: View {
    @State private var auth: AuthController
    @State private var session: AppSession
    @State private var servicePreferences: ServicePreferences
    @State private var display = DisplayPreferences()
    @State private var isLaunching = true
    @State private var preferenceSync = PreferenceSync()
    @State private var keyring = DeviceKeyring()
    @State private var appSignIn = AppSignInCenter()
    @State private var launchRoute: DuovaLaunchRouteStore
    /// The launched service's live surfaces. Kept across lock, background and
    /// layout changes; dropped only when the account changes.
    @State private var immersive: ImmersiveCoordinator?
    @State private var showDeviceLink = false
    @State private var approvingDevice: LinkedDevice?
    /// Requests already shown this launch ("Later" isn't asked again).
    @State private var shownRequests: Set<UUID> = []

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    init() {
        let auth = AuthController()
        _auth = State(initialValue: auth)
        _session = State(initialValue: AppSession(accountID: auth.account?.id))
        _servicePreferences = State(initialValue: ServicePreferences(accountID: auth.account?.id))
        let route = DuovaLaunchRouteStore(accountID: auth.account?.id)
        _launchRoute = State(initialValue: route)
        // A committed service reopens directly, with no Duova launch animation.
        _isLaunching = State(initialValue: route.committedService == nil)
    }

    private var reducesMotion: Bool { systemReduceMotion || display.motion == .reduced }

    /// The committed service for the signed-in account, if any.
    private var immersiveService: ServiceID? {
        if case .immersive(let service) = launchRoute.route(for: auth.account?.id) { return service }
        return nil
    }

    var body: some View {
        ZStack {
            destination
                .accessibilityHidden(isLaunching)
                .allowsHitTesting(!isLaunching)

            if isLaunching {
                LaunchView(variant: session.launchVariant, reducesMotion: reducesMotion, onFinish: finishLaunch)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        // Under everything, so no edge of the window can ever show as a black bar.
        .background { DuovaBackdrop() }
        .pageSheetHost()
        .scrollIndicators(.hidden, axes: [.vertical, .horizontal])
        .environment(auth)
        .environment(session)
        .environment(servicePreferences)
        .environment(display)
        .environment(keyring)
        .environment(appSignIn)
        .environment(launchRoute)
        .duovaTheme(style: display.colorStyle)
        .bookPostureAware()
        .preferredColorScheme(display.appearance.colorScheme)
        .animation(.easeInOut(duration: reducesMotion ? 0.1 : 0.3), value: auth.phase)
        .animation(.easeInOut(duration: reducesMotion ? 0.1 : 0.3), value: immersiveService)
        .onChange(of: auth.account?.id, initial: true) { _, id in
            session.activate(accountID: id)
            servicePreferences.activate(accountID: id)
            launchRoute.activate(accountID: id)
            if immersive?.accountID != id { immersive = nil }
        }
        .onChange(of: immersiveService, initial: true) { _, service in
            syncImmersive(service)
        }
        .task(id: auth.account?.id) {
            await auth.verifyAppleCredential()
            await auth.verifyCloudSession()
            await keyring.prepare(accountID: auth.account?.id)
        }
        // Encrypted sync starts only once this device has the account's keys.
        .task(id: keyring.readyAccountID) {
            guard let accountID = keyring.readyAccountID else {
                preferenceSync.stop()
                appSignIn.stop()
                return
            }
            await auth.syncPrivateName()
            await preferenceSync.start(accountID: accountID, current: preferenceSnapshot, apply: apply)
            // Inside a launched service nothing else signs in to anything.
            if launchRoute.committedService == nil {
                appSignIn.start(accountID: accountID, priority: session.favorites)
            }
            await watchForNewDevices()
        }
        .task(id: keyring.state) {
            guard case .waitingForApproval = keyring.state else { return }
            showDeviceLink = true
            await keyring.waitForApproval()
        }
        .onChange(of: preferenceSnapshot) { _, snapshot in preferenceSync.changed(snapshot) }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                auth.sceneDidBecomeActive()
                if keyring.state == .offline {
                    Task { await keyring.prepare(accountID: auth.account?.id) }
                }
            case .background:
                auth.sceneDidEnterBackground()
                immersive?.saveCheckpointNow()
            default: break
            }
            if newPhase != .active { session.recordInactive() }
        }
    }

    /// Creates the service's surfaces once when a launch is committed and keeps
    /// them across visits to Splitter until the account changes.
    private func syncImmersive(_ service: ServiceID?) {
        guard let service, let accountID = auth.account?.id else { return }
        if let immersive, immersive.service == service, immersive.accountID == accountID { return }
        guard let adapter = SocialAdapterRegistry.adapter(for: service) else { return }
        appSignIn.stop()
        immersive = ImmersiveCoordinator(
            accountID: accountID, service: service, adapter: adapter, preferences: servicePreferences)
    }

    /// Everything that syncs with the account (App Lock settings stay on the device).
    private var preferenceSnapshot: PreferenceSnapshot {
        PreferenceSnapshot(
            appearance: display.appearance, colorStyle: display.colorStyle, motion: display.motion,
            defaults: servicePreferences.defaults,
            overrides: Dictionary(uniqueKeysWithValues: servicePreferences.overrides.map { ($0.key.rawValue, $0.value) }),
            favorites: session.favorites.map(\.rawValue))
    }

    private func apply(_ snapshot: PreferenceSnapshot) {
        display.appearance = snapshot.appearance
        display.colorStyle = snapshot.colorStyle
        display.motion = snapshot.motion
        servicePreferences.replaceAll(
            defaults: snapshot.defaults,
            overrides: Dictionary(uniqueKeysWithValues: snapshot.overrides.compactMap { key, value in
                ServiceID(rawValue: key).map { ($0, value) }
            }))
        session.replaceFavorites(snapshot.favorites.compactMap(ServiceID.init(rawValue:)))
    }

    @ViewBuilder
    private var destination: some View {
        switch auth.phase {
        case .signedOut:
            SignInView().transition(.opacity)
        case .locked:
            LockView().transition(.opacity)
        case .active:
            if immersiveService != nil {
                // The service is the app now: no shell, no Duova sheets.
                if let immersive {
                    ImmersiveServiceHost(coordinator: immersive, onSuspend: { launchRoute.park() })
                        .transition(.opacity)
                } else {
                    Color(.systemBackground).ignoresSafeArea()
                }
            } else {
                MainShell(startInSplitter: launchRoute.isParked)
                    .transition(.opacity)
                    .pageSheet(isPresented: $showDeviceLink) { DeviceLinkView() }
                    .pageSheet(item: $approvingDevice) { DeviceApprovalView(device: $0) }
            }
        }
    }

    /// On a device with the keys, offers each new device's request once.
    private func watchForNewDevices() async {
        while !Task.isCancelled {
            if scenePhase == .active {
                await keyring.refreshDevices()
                if approvingDevice == nil, auth.phase == .active, immersiveService == nil,
                   let request = keyring.pendingDevices.first(where: { !shownRequests.contains($0.id) }) {
                    shownRequests.insert(request.id)
                    approvingDevice = request
                }
            }
            try? await Task.sleep(for: .seconds(15))
        }
    }

    private func finishLaunch() {
        withAnimation(.easeOut(duration: reducesMotion ? 0.15 : 0.30)) {
            isLaunching = false
        }
    }
}

#Preview {
    RootView()
}
