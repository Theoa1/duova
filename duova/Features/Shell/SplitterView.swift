import SwiftUI

/// The encrypted launch record is the source of truth, never placeholder workspaces.
struct SplitterView: View {
    @Environment(DuovaLaunchRouteStore.self) private var route
    @Environment(\.duovaTheme) private var theme
    @State private var resumeFailed = false

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
                        Image(systemName: "rectangle.stack")
                            .font(.title2)
                            .foregroundStyle(theme.accent)
                        Text(service.rawValue.capitalized).font(.title3.bold())
                        Spacer()
                        Text("Preserved").font(.caption.weight(.semibold))
                            .foregroundStyle(theme.accent)
                    }
                    Label("Private sign-in session", systemImage: "lock")
                    Label("Page, scroll and companion checkpoint", systemImage: "rectangle.split.2x1")
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
        .alert("Couldn’t resume", isPresented: $resumeFailed) {
            Button("OK", role: .cancel) {}
        } message: { Text("The secure launch record could not be saved. Please try again.") }
    }
}
