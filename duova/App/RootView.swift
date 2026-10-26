import SwiftUI

/// Hosts the launch overlay above the app's first destination.
///
/// The destination (Welcome for first use, Library afterwards) is built
/// immediately underneath the launch overlay, so the hand-off is a simple
/// crossfade and no work is deferred until the animation ends.
struct RootView: View {
    @State private var session = AppSession()
    @State private var isLaunching = true

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            destination
                .accessibilityHidden(isLaunching)
                .allowsHitTesting(!isLaunching)

            if isLaunching {
                LaunchView(variant: session.launchVariant, onFinish: finishLaunch)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .environment(session)
        .duovaTheme()
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active { session.recordInactive() }
        }
    }

    @ViewBuilder
    private var destination: some View {
        if session.hasCompletedWelcome {
            LibraryView()
                .transition(.opacity)
        } else {
            WelcomeView()
                .transition(.opacity)
        }
    }

    private func finishLaunch() {
        withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.30)) {
            isLaunching = false
        }
    }
}

#Preview {
    RootView()
}
