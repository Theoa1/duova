import SwiftUI

/// Library filters: the two virtual filters plus the blueprint categories.
enum LibraryFilter: Hashable, Identifiable {
    case all
    case favorites
    case category(ServiceCategory)

    var id: String {
        switch self {
        case .all: "all"
        case .favorites: "favorites"
        case .category(let category): category.id
        }
    }

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .favorites: String(localized: "Favorites")
        case .category(let category): category.title
        }
    }

    static let ordered: [LibraryFilter] =
        [.all, .favorites] + ServiceCategory.allCases.map { .category($0) }
}

/// Searchable, filterable list of catalog services. Works entirely offline
/// from the bundled catalog.
struct LibraryView: View {
    @Environment(\.duovaTheme) private var theme
    @Environment(AppSession.self) private var session
    @Environment(\.bookPosture) private var book
    @Environment(\.navigationAreaWidth) private var navigationAreaWidth

    /// Owned by the app shell, which hosts the search field.
    @Binding var query: String
    @State private var filter: LibraryFilter = .all
    @State private var selected: Service?

    private var results: [Service] {
        ServiceCatalog.all.filter { service in
            guard service.matches(query) else { return false }
            switch filter {
            case .all: return true
            case .favorites: return session.isFavorite(service.id)
            case .category(let category): return service.category == category
            }
        }
    }

    var body: some View {
        NavigationStack {
            // The list is full screen in every orientation: cards run to within
            // a small margin of both side edges and scroll under the system's
            // glass bars and Duova's navigation buttons. Only the star on cards
            // in the right-hand column moves in, clear of those buttons.
            GeometryReader { geo in
                let insets = geo.safeAreaInsets
                let width = geo.size.width - DuovaMetrics.screenMargin * 2 + insets.leading + insets.trailing
                // Where the middle of the screen falls, measured from the start of the cards.
                let middle = (geo.size.width + insets.leading + insets.trailing) / 2 - DuovaMetrics.screenMargin

                ScrollView {
                    content(availableWidth: width, middle: middle)
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, DuovaMetrics.screenMargin, for: .scrollContent)
                .scrollDismissesKeyboard(.interactively)
                .safeAreaBar(edge: .top, spacing: 0) {
                    FilterRow(selection: $filter)
                        .padding(.vertical, 6)
                }
                .ignoresSafeArea(.container, edges: .horizontal)
            }
            .background { DuovaBackdrop() }
            .navigationTitle("Apps")
        }
        .pageSheet(item: $selected, resizable: true) { service in
            ServiceDetailView(service: service)
        }
    }

    @ViewBuilder
    private func content(availableWidth: CGFloat, middle: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if results.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else if book?.axis == .horizontal {
                // Open side by side: the services are laid out like a book, the
                // first half on the left page and the rest on the right, with the
                // fold in the gutter between them so no card ever sits across it.
                let gutter = DuovaMetrics.screenMargin * 2
                let leftWidth = max(0, middle - gutter / 2)
                let rightWidth = max(0, availableWidth - leftWidth - gutter)
                let half = (results.count + 1) / 2
                HStack(alignment: .top, spacing: gutter) {
                    grid(Array(results.prefix(half)), width: leftWidth, touchesRightEdge: false)
                        .frame(width: leftWidth)
                    grid(Array(results.dropFirst(half)), width: rightWidth, touchesRightEdge: true)
                        .frame(width: rightWidth)
                }
            } else {
                grid(results, width: availableWidth, touchesRightEdge: true)
            }
        }
        .padding(.vertical, 8)
    }

    /// Column count follows the real width, so portrait, landscape, iPad and
    /// each page of an open device get a sensible grid.
    private func grid(_ services: [Service], width: CGFloat, touchesRightEdge: Bool) -> some View {
        let spacing = DuovaMetrics.gridSpacing
        let columns = max(1, Int((width + spacing) / (300 + spacing)))
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns),
            spacing: spacing
        ) {
            ForEach(Array(services.enumerated()), id: \.element.id) { index, service in
                // Cards in the right-hand column sit under the navigation
                // buttons, so their star moves in to stay reachable.
                let isRightColumn = touchesRightEdge && index % columns == columns - 1
                ServiceRow(
                    service: service,
                    starInset: isRightColumn ? max(0, navigationAreaWidth - DuovaMetrics.screenMargin) : 0,
                    isFavorite: session.isFavorite(service.id),
                    open: { selected = service },
                    toggleFavorite: { session.toggleFavorite(service.id) }
                )
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView.search(text: query)
        } else if filter == .favorites {
            ContentUnavailableView(
                "No favorites yet",
                systemImage: "star",
                description: Text("Tap the star on a service to keep it here.")
            )
        } else if case .category(let category) = filter {
            ContentUnavailableView(
                "Nothing here yet",
                systemImage: category.symbol,
                description: Text("No \(category.longTitle) services are in the catalog yet.")
            )
        } else {
            ContentUnavailableView("No services", systemImage: "square.grid.2x2")
        }
    }
}

private struct FilterRow: View {
    @Environment(\.duovaTheme) private var theme
    @Binding var selection: LibraryFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(LibraryFilter.ordered) { item in
                        chip(item)
                    }
                }
            }
            .padding(.leading, DuovaMetrics.screenMargin)
            .padding(.trailing, DuovaMetrics.screenMargin)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func chip(_ item: LibraryFilter) -> some View {
        let isSelected = item == selection
        let shape = RoundedRectangle(cornerRadius: DuovaMetrics.cornerRadius, style: .continuous)
        return Button {
            selection = item
        } label: {
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? theme.onAccent : theme.textPrimary)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .glassEffect(
                    isSelected
                        ? .regular.tint(theme.accent.opacity(0.75)).interactive()
                        : .regular.interactive(),
                    in: shape
                )
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct StatusBadge: View {
    @Environment(\.duovaTheme) private var theme
    let status: CompatibilityStatus

    var body: some View {
        Label(status.title, systemImage: status.symbol)
            .font(.caption2.weight(.semibold))
            // Darker text in light mode keeps the label readable on its pale tint.
            .foregroundStyle(theme.tint(for: status).mix(with: theme.isDark ? .white : .black, by: theme.isDark ? 0.25 : 0.45))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.tint(for: status).opacity(theme.isDark ? 0.22 : 0.16))
            )
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Library card: a liquid-glass surface holding a glass icon, the service name,
/// a quiet category line and a compact status tag, with a separate favorite control.
private struct ServiceRow: View {
    @Environment(\.duovaTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let service: Service
    /// Extra space after the star, keeping it clear of the navigation buttons.
    var starInset: CGFloat = 0
    let isFavorite: Bool
    let open: () -> Void
    let toggleFavorite: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DuovaMetrics.cornerRadius, style: .continuous)

        HStack(spacing: 2) {
            Button(action: open) {
                label
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(shape)
            }
            .buttonStyle(CardPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("Shows details"))

            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.body)
                    .foregroundStyle(isFavorite ? (theme.style == .duova ? DuovaPalette.amber : theme.textPrimary) : theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(isFavorite ? "Remove \(service.name) from favorites" : "Add \(service.name) to favorites"))
        }
        .padding(.leading, 12)
        .padding(.trailing, 4 + starInset)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: shape)
    }

    @ViewBuilder
    private var label: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                ServiceIcon(id: service.id, size: 52)
                details
            }
        } else {
            HStack(spacing: 12) {
                ServiceIcon(id: service.id, size: 48)
                details
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(service.name)
                .font(.headline)
                .foregroundStyle(theme.textPrimary)
            Text(service.category.longTitle)
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
            StatusBadge(status: service.status)
                .padding(.top, 3)
        }
    }
}

/// Gentle press feedback for glass cards.
private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    LibraryView(query: .constant(""))
        .environment(AppSession(defaults: UserDefaults(suiteName: "duova.preview") ?? .standard))
        .duovaTheme()
}
