import SwiftUI

/// The encrypted launch record is the source of truth, never placeholder workspaces.
struct SplitterView: View {
    @Environment(DuovaLaunchRouteStore.self) private var route
    @Environment(AuthController.self) private var auth
    @State private var checkpoint: ImmersiveCheckpoint?
    @Environment(\.duovaTheme) private var theme
    @State private var resumeFailed = false

    private func pageName(_ path: String) -> String {
        if path == "/" { return "Feed" }
        if path.hasPrefix("/reel") { return "Reels" }
        if path.hasPrefix("/direct/") { return "Messages" }
        if path.hasPrefix("/explore/") { return "Explore" }
        if path.hasPrefix("/p/") { return "Post" }
        return "Profile"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Your preserved workspace")
                .font(.title2.bold())
                .foregroundStyle(theme.textPrimary)
            Text("Hold with three fingers, then pull down to return here. Resume keeps the current page when it is still in memory.")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
            if let service = route.committedService {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        ServiceIcon(id: service, size: 48)
                        Text(service.rawValue.capitalized).font(.title3.bold())
                        Spacer()
                        Text("Preserved").font(.caption.weight(.semibold))
                            .foregroundStyle(theme.accent)
                    }
                    Label("Private sign-in session", systemImage: "lock")
                    if let checkpoint {
                        Label("Main: " + pageName(checkpoint.primaryRoute), systemImage: "rectangle")
                        if let kind = checkpoint.companionKind {
                            Label("Companion: " + kind.rawValue.capitalized, systemImage: "rectangle.split.2x1")
                        }
                        Label("Scroll positions saved", systemImage: "arrow.up.and.down")
                        if !(checkpoint.primaryState?.media.isEmpty ?? true) {
                            Label("Playback position saved", systemImage: "play.circle")
                        }
                    } else {
                        Label("Live session retained", systemImage: "rectangle.stack")
                    }
                    if let date = route.savedAt {
                        Text(date, format: .dateTime.month().day().hour().minute())
                            .font(.caption).foregroundStyle(theme.textSecondary)
                    }
                    Button {
                        resumeFailed = !route.commit(service)
                    } label: {
                        Label("Resume workspace", systemImage: "arrow.up.right")
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                    .tint(theme.accent)
                }
                .foregroundStyle(theme.textPrimary)
                .padding(20)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 24))
            } else {
                ContentUnavailableView("No preserved workspaces",
                    systemImage: "rectangle.stack",
                    description: Text("Open Instagram from Apps to start a workspace."))
            }
            Text("After a system restart, supported page state is restored from an encrypted checkpoint. Unsaved website drafts may require the live session.")
                .font(.footnote).foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: 680, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: route.savedAt) {
            guard let accountID = auth.account?.id, let service = route.committedService else {
                checkpoint = nil
                return
            }
            checkpoint = ImmersiveCheckpointStore().load(accountID: accountID, service: service)
        }
        .alert("Couldn’t resume", isPresented: $resumeFailed) {
            Button("OK", role: .cancel) {}
        } message: { Text("The secure launch record could not be saved. Please try again.") }
    }
}
