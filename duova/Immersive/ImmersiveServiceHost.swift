import SwiftUI

/// The whole window while a service is launched. Shows the live service; while
/// the first page is on its way it shows a quiet system-colored surface, and
/// if the site or the connection fails it shows a plain retry in place. Never
/// a way back to the library.
struct ImmersiveServiceHost: View {
    let coordinator: ImmersiveCoordinator

    var body: some View {
        ZStack {
            ImmersiveHostRepresentable(coordinator: coordinator)
                .ignoresSafeArea()

            switch coordinator.phase {
            case .loading:
                Color(.systemBackground)
                    .ignoresSafeArea()
                    .overlay { ProgressView().controlSize(.large) }
                    .transition(.opacity)
            case .offline:
                ServiceFallbackView(isOffline: true) { coordinator.retry() }
                    .transition(.opacity)
            case .unavailable:
                ServiceFallbackView(isOffline: false) { coordinator.retry() }
                    .transition(.opacity)
            case .ready:
                EmptyView()
            }
        }
        .animation(.easeOut(duration: 0.25), value: coordinator.phase)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(nil)
    }
}

private struct ImmersiveHostRepresentable: UIViewControllerRepresentable {
    let coordinator: ImmersiveCoordinator

    func makeUIViewController(context: Context) -> ImmersiveHostController {
        ImmersiveHostController(coordinator: coordinator)
    }

    func updateUIViewController(_ controller: ImmersiveHostController, context: Context) {
        // Reading these here re-runs the update when the companion changes.
        _ = coordinator.companionWanted
        _ = coordinator.splitRatio
        controller.companionDidChange()
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
