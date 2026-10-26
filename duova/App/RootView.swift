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

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    init() {
        let auth = AuthController()
        _auth = State(initialValue: auth)
        _session = State(initialValue: AppSession(accountID: auth.account?.id))
        _servicePreferences = State(initialValue: ServicePreferences(accountID: auth.account?.id))
    }

    private var reducesMotion: Bool { systemReduceMotion || display.motion == .reduced }

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
        .environment(auth)
        .environment(session)
        .environment(servicePreferences)
        .environment(display)
        .duovaTheme(style: display.colorStyle)
        .bookPostureAware()
        .preferredColorScheme(display.appearance.colorScheme)
        .animation(.easeInOut(duration: reducesMotion ? 0.1 : 0.3), value: auth.phase)
        .onChange(of: auth.account?.id, initial: true) { _, id in
            session.activate(accountID: id)
            servicePreferences.activate(accountID: id)
        }
        .task { await auth.verifyAppleCredential() }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active: auth.sceneDidBecomeActive()
            case .background: auth.sceneDidEnterBackground()
            default: break
            }
            if newPhase != .active { session.recordInactive() }
        }
    }

    @ViewBuilder
    private var destination: some View {
        switch auth.phase {
        case .signedOut:
            SignInView().transition(.opacity)
        case .locked:
            LockView().transition(.opacity)
        case .active:
            MainShell().transition(.opacity)
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
