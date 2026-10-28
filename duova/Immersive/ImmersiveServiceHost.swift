import SwiftUI

/// The whole window while a service is launched. Shows the live service; while
/// the first page is on its way it shows a quiet system-colored surface, and
/// if the site or the connection fails it shows a plain retry in place. Never
/// a destructive reset when returning to Splitter.
struct ImmersiveServiceHost: View {
    let coordinator: ImmersiveCoordinator
    var onSuspend: () -> Bool = { false }
    @State private var suspensionFailed = false

    var body: some View {
        ImmersiveHostRepresentable(coordinator: coordinator, onSuspend: onSuspend)
            .ignoresSafeArea()
        .accessibilityAction(named: "Return to Splitter") {
            Task { await coordinator.captureCheckpoint(); suspensionFailed = !onSuspend() }
        }
        .alert("Workspace", isPresented: Binding(
            get: { coordinator.navigationNotice != nil || suspensionFailed },
            set: { if !$0 { coordinator.navigationNotice = nil; suspensionFailed = false } }
        )) {
            Button("OK", role: .cancel) { coordinator.navigationNotice = nil; suspensionFailed = false }
        } message: {
            Text(coordinator.navigationNotice ?? "Couldn’t save the workspace. Your current page is still open.")
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(nil)
    }
}

private struct ImmersiveHostRepresentable: UIViewControllerRepresentable {
    let coordinator: ImmersiveCoordinator
    var onSuspend: () -> Bool

    func makeUIViewController(context: Context) -> ImmersiveHostController {
        let controller = ImmersiveHostController(coordinator: coordinator)
        controller.onSuspend = onSuspend
        return controller
    }

    func updateUIViewController(_ controller: ImmersiveHostController, context: Context) {
        // Reading these here re-runs the update when the companion changes.
        _ = coordinator.companionWanted
        _ = coordinator.companionStatus
        _ = coordinator.splitRatio
        _ = coordinator.phase
        controller.onSuspend = onSuspend
        controller.companionDidChange()
    }
}


struct ImmersiveStatusView: View {
    let coordinator: ImmersiveCoordinator
    var body: some View {
        switch coordinator.phase {
        case .loading:
            Color(.systemBackground).ignoresSafeArea()
                .overlay { ProgressView().controlSize(.large) }
        case .offline:
            ServiceFallbackView(isOffline: true) { coordinator.retry() }
        case .unavailable:
            ServiceFallbackView(isOffline: false) { coordinator.retry() }
        case .ready:
            EmptyView()
        }
    }
}

/// System-styled retry surface for the launched service. Deliberately plain:
/// no Duova name, mark or color, nothing that looks like an exit.
struct ServiceFallbackView: View {
    let isOffline: Bool
    let retry: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: isOffline ? "wifi.slash" : "exclamationmark.triangle")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.secondary)
                Text(isOffline ? String(localized: "You're offline") : String(localized: "This page can't be loaded"))
                    .font(.headline)
                Text(isOffline
                     ? String(localized: "It will reconnect when you're back online.")
                     : String(localized: "Try again in a moment."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(String(localized: "Try Again"), action: retry)
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
            }
            .padding(32)
        }
    }
}
