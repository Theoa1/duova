import SwiftUI

/// One system Liquid Glass surface, with no colored fill or web blur imitation.
struct InstagramNavigationBar: View {
    let coordinator: ImmersiveCoordinator

    var body: some View {
        HStack(spacing: 0) {
            item("Home", symbol: "house", path: "/")
            item("Explore", symbol: "magnifyingglass", path: "/explore/")
            item("Reels", symbol: "play.rectangle", path: "/reels/")
            item("Messages", symbol: "paperplane", path: "/direct/inbox/")
        }
        .padding(6)
        .glassEffect(.regular.interactive(), in: Capsule())
        .padding(4)
    }

    private func item(_ title: String, symbol: String, path: String) -> some View {
        Button { coordinator.navigatePrimary(path) } label: {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct CompanionNavigation: View {
    let coordinator: ImmersiveCoordinator
    private var title: String {
        switch coordinator.companionKind {
        case .comments: "Comments"
        case .messages: "Messages"
        case .explore: "Explore"
        case .profile: "Profile"
        case .post: "Post"
        default: "Choose content"
        }
    }
    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Menu {
                Button("Comments on current post or Reel", systemImage: "bubble.right") {
                    coordinator.selectCompanion(.comments)
                }
                Button("Messages", systemImage: "paperplane") { coordinator.selectCompanion(.messages) }
                Button("Explore", systemImage: "magnifyingglass") { coordinator.selectCompanion(.explore) }
            } label: {
                HStack(spacing: 6) {
                    Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14).frame(minHeight: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Companion: " + title)
        }
        .padding(4)
    }
}
