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
///
/// The shell supplies the title row (the title or search field, plus the
/// navigation buttons). It hides while scrolling down and returns on any scroll up.
struct LibraryView<Header: View>: View {
    @Environment(\.duovaTheme) private var theme
    @Environment(AppSession.self) private var session
    @Environment(AppSignInCenter.self) private var signIn
    @Environment(DuovaLaunchRouteStore.self) private var launchRoute
    @Environment(\.bookPosture) private var book

    /// Owned by the app shell, which hosts the search field.
    @Binding var query: String
    @ViewBuilder var header: Header
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

    /// The title row is tucked away while scrolling down through the apps and
    /// slides back the moment you scroll up, wherever you are in the list.
    @State private var titleHidden = false
    @State private var titleHeight: CGFloat = 0
    @State private var topHeight: CGFloat = 0
    @State private var isScrolled = false
    /// Where the scroll last changed direction.
    @State private var scrollTurn: CGFloat = 0

    var body: some View {
        NavigationStack {
            // The list is full screen in every orientation: cards run to within
            // a small margin of both side edges. The title row and filters float
            // over the top of it; the title row keeps clear of the camera and
            // status bar, wherever the system puts them.
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
                .contentMargins(.top, topHeight, for: .scrollContent)
                .scrollDismissesKeyboard(.interactively)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { old, new in
                    updateTitle(scrolledFrom: old, to: new)
                }
                .overlay(alignment: .top) {
                    topBar(insets: insets)
                }
                .ignoresSafeArea(.container, edges: .horizontal)
            }
            .background { DuovaBackdrop() }
            .toolbar(.hidden, for: .navigationBar)
        }
        .morphCard(item: $selected, from: { "service.\($0.id.rawValue)" }) { service in
            ServiceDetailView(service: service) {
                selected = nil
                launch(service)
            }
        }
    }

    /// Tapping an app opens it; one that can't open yet shows its card instead.
    private func tap(_ service: Service) {
        if service.canLaunch { launch(service) } else { selected = service }
    }

    /// Launching hands the whole app to the service. The commitment is written
    /// first, so a relaunch returns to the service, then the root swaps routes.
    private func launch(_ service: Service) {
        guard service.canLaunch else { return }
        if !launchRoute.commit(service.id) {
            // Couldn't be remembered durably; show the card rather than open
            // something that wouldn't come back.
            selected = service
        }
    }

    /// The title row over the filter chips. Hiding the title slides the pair up
    /// so the chips take its place; nothing underneath moves.
    private func topBar(insets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            header
                .padding(.leading, insets.leading + DuovaMetrics.screenMargin)
                .padding(.trailing, insets.trailing + DuovaMetrics.screenMargin)
                .padding(.top, 4)
                .padding(.bottom, 2)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { titleHeight = $0 }
                .opacity(titleHidden ? 0 : 1)
                .allowsHitTesting(!titleHidden)
                .accessibilityHidden(titleHidden)
            FilterRow(selection: $filter)
                .padding(.vertical, 6)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { topHeight = $0 }
        .offset(y: titleHidden ? -titleHeight : 0)
        .background(alignment: .bottom) {
            // A soft frosted fade, only once cards pass underneath. No edge line.
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(LinearGradient(
                    stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                    startPoint: .top, endPoint: .bottom))
                .padding(.bottom, -16)
                .offset(y: titleHidden ? -titleHeight : 0)
                .ignoresSafeArea(edges: .top)
                .opacity(isScrolled ? 1 : 0)
                .allowsHitTesting(false)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: titleHidden)
        .animation(.easeOut(duration: 0.2), value: isScrolled)
    }

    /// Scrolling down tucks the title away; any scroll up brings it straight back.
    /// It always shows near the top, and while there's a search in progress.
    private func updateTitle(scrolledFrom old: CGFloat, to new: CGFloat) {
        isScrolled = new > 2
        if new < 24 || !query.isEmpty {
            titleHidden = false
            scrollTurn = new
        } else if titleHidden {
            // Hidden: follow the scroll down; a short scroll back up shows it.
            if new > scrollTurn { scrollTurn = new } else if scrollTurn - new > 16 { titleHidden = false; scrollTurn = new }
        } else {
            // Shown: follow the scroll up; a longer scroll down hides it.
            if new < scrollTurn { scrollTurn = new } else if new - scrollTurn > 32 { titleHidden = true; scrollTurn = new }
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
                    grid(Array(results.prefix(half)), width: leftWidth)
                        .frame(width: leftWidth)
                    grid(Array(results.dropFirst(half)), width: rightWidth)
                        .frame(width: rightWidth)
                }
            } else {
                grid(results, width: availableWidth)
            }
        }
        .padding(.vertical, 8)
    }

    /// Column count follows the real width, so portrait, landscape, iPad and
    /// each page of an open device get a sensible grid.
    private func grid(_ services: [Service], width: CGFloat) -> some View {
        let spacing = DuovaMetrics.gridSpacing
        let columns = max(1, Int((width + spacing) / (300 + spacing)))
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns),
            spacing: spacing
        ) {
            ForEach(services) { service in
                ServiceRow(
                    service: service,
                    isFavorite: session.isFavorite(service.id),
                    signIn: signIn.status(for: service.id),
                    open: { tap(service) },
                    showDetails: { selected = service },
                    toggleFavorite: { session.toggleFavorite(service.id) }
                )
                .morphSource("service.\(service.id.rawValue)")
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
    let isFavorite: Bool
    let signIn: AppSignInStatus
    let open: () -> Void
    let showDetails: () -> Void
    let toggleFavorite: () -> Void

    @State private var isPressed = false
    @State private var detailsShown = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DuovaMetrics.cornerRadius, style: .continuous)

        HStack(spacing: 2) {
            // Tap opens the app; a long press shows its card.
            label
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(shape)
                .opacity(isPressed ? 0.7 : 1)
                .scaleEffect(isPressed ? 0.985 : 1)
                .animation(.easeOut(duration: 0.12), value: isPressed)
                .onTapGesture(perform: open)
                .onLongPressGesture(minimumDuration: 0.35) {
                    detailsShown += 1
                    showDetails()
                } onPressingChanged: { isPressed = $0 }
                .sensoryFeedback(.impact(weight: .medium), trigger: detailsShown)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(Text(service.canLaunch ? "Opens \(service.name)" : "Shows details"))
                .accessibilityAction(named: Text("Show details"), showDetails)

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
        .padding(.trailing, 4)
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
            AppSignInTag(status: signIn)
                .padding(.top, 1)
        }
    }
}

#Preview {
    LibraryView(query: .constant("")) {
        Text("Apps").font(.largeTitle.bold())
    }
        .environment(AppSession(defaults: UserDefaults(suiteName: "duova.preview") ?? .standard))
        .environment(AppSignInCenter())
        .environment(DuovaLaunchRouteStore())
        .duovaTheme()
}
