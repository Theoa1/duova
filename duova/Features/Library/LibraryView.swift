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

    @State private var query = ""
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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FilterRow(selection: $filter)

                    if results.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 320), spacing: 12)],
                            spacing: 12
                        ) {
                            ForEach(results) { service in
                                ServiceRow(
                                    service: service,
                                    isFavorite: session.isFavorite(service.id),
                                    open: { selected = service },
                                    toggleFavorite: { session.toggleFavorite(service.id) }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    Text("Services shown here are candidates under review. Names and logos belong to their owners and are shown for identification only.")
                        .font(.footnote)
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .background { DuovaBackdrop() }
            .navigationTitle("Apps")
            .searchable(text: $query, prompt: "Search services")
            .sheet(item: $selected) { service in
                ServiceDetailView(service: service)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
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
            HStack(spacing: 8) {
                ForEach(LibraryFilter.ordered) { item in
                    let isSelected = item == selection
                    Button {
                        selection = item
                    } label: {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isSelected ? Color.white : theme.textPrimary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(
                                Capsule().fill(isSelected ? Color(hex: 0x3F72C4) : theme.card)
                            )
                            .overlay(Capsule().strokeBorder(theme.border, lineWidth: isSelected ? 0 : 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

struct StatusBadge: View {
    @Environment(\.duovaTheme) private var theme
    let status: CompatibilityStatus

    var body: some View {
        Label(status.title, systemImage: status.symbol)
            .font(.caption.weight(.semibold))
            // Darker text in light mode keeps the label readable on its pale tint.
            .foregroundStyle(status.tint.mix(with: .black, by: theme.isDark ? 0 : 0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(status.tint.opacity(0.16)))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ServiceRow: View {
    @Environment(\.duovaTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let service: Service
    let isFavorite: Bool
    let open: () -> Void
    let toggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: open) {
                label
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("Shows details"))

            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(isFavorite ? DuovaPalette.amber : theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(isFavorite ? "Remove \(service.name) from favorites" : "Add \(service.name) to favorites"))
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
    }

    @ViewBuilder
    private var label: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                ServiceIcon(id: service.id, size: 56)
                details
            }
        } else {
            HStack(spacing: 14) {
                ServiceIcon(id: service.id, size: 52)
                details
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(service.name)
                .font(.headline)
                .foregroundStyle(theme.textPrimary)
            Text(service.category.longTitle)
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
            StatusBadge(status: service.status)
                .padding(.top, 2)
        }
    }
}

#Preview {
    LibraryView()
        .environment(AppSession(defaults: UserDefaults(suiteName: "duova.preview") ?? .standard))
        .duovaTheme()
}
