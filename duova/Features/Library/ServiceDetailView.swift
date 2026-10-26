import SwiftUI

/// Detail sheet for a catalog service. Describes the true status of the
/// service and offers only actions that work today (favoriting).
struct ServiceDetailView: View {
    @Environment(\.duovaTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session

    let service: Service

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ServiceIcon(id: service.id, size: 88)
                        .shadow(color: service.accent.opacity(0.25), radius: 18, y: 6)
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
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(theme.border, lineWidth: 1))

                    Button {
                        session.toggleFavorite(service.id)
                    } label: {
                        Label(
                            session.isFavorite(service.id) ? "Remove from favorites" : "Add to favorites",
                            systemImage: session.isFavorite(service.id) ? "star.fill" : "star"
                        )
                    }
                    .buttonStyle(DuovaPrimaryButtonStyle())

                    Text("\(service.name) is an independent product. Duova is not affiliated with, sponsored by, or endorsed by its owner.")
                        .font(.footnote)
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 520)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background { DuovaBackdrop() }
            .navigationTitle(service.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
