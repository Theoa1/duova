import SwiftUI

/// Detail card for a catalog service. Describes the true status of the
/// service and offers only actions that work today: favoriting, and signing
/// in so the app's session is ready. The full saved-login page morphs out of
/// the sign-in section and lands over this card. There's no title bar: the name
/// is in the card itself, and tapping outside (or the X on a closed phone) closes it.
struct ServiceDetailView: View {
    @Environment(\.duovaTheme) private var theme
    @Environment(AppSession.self) private var session

    let service: Service

    @State private var showsSavedLogin = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ServiceIcon(id: service.id, size: 96)
                    .shadow(color: service.accent.opacity(0.30), radius: 20, y: 6)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text(service.name)
                        .font(.title.bold())
                        .foregroundStyle(theme.textPrimary)
                    Label(service.category.longTitle, systemImage: service.category.symbol)
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 10) {
                    StatusBadge(status: service.status)
                    Text(service.status.explanation)
                        .font(.body)
                        .foregroundStyle(theme.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DuovaMetrics.cornerRadius, style: .continuous))

                AppSignInSection(service: service, openSavedLogin: { showsSavedLogin = true })

                Button {
                    session.toggleFavorite(service.id)
                } label: {
                    Label(
                        session.isFavorite(service.id) ? "Remove from favorites" : "Add to favorites",
                        systemImage: session.isFavorite(service.id) ? "star.fill" : "star"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: DuovaMetrics.cornerRadius))
                .controlSize(.large)
                .tint(theme.accent)
                .foregroundStyle(theme.onAccent)

                Text("\(service.name) is an independent product. Duova is not affiliated with, sponsored by, or endorsed by its owner.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background { DuovaBackdrop() }
        .morphCard(isPresented: $showsSavedLogin, from: "login.\(service.id.rawValue)") {
            SavedLoginView(service: service)
        }
    }
}
