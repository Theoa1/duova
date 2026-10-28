import SwiftUI

/// The signed-in app.
///
/// The Apps page is full screen. Its title row carries the navigation on the
/// right: Apps, Profile and Search as three separate liquid-glass buttons. The
/// row keeps clear of the status bar wherever the system puts it, so the
/// buttons sit in the top-right corner when the status bar runs along the top,
/// and just inside it when the status bar runs down the right edge.
///
/// Profile isn't a separate screen. Choosing it slides a panel in from the right
/// over the apps, which go inactive underneath; tap them or swipe the panel away
/// to close it. In landscape the panel reaches exactly the middle of the screen.
///
/// This shell is not shown during sign-in, the lock screen, or (later) inside an
/// immersive third-party service.
struct MainShell: View {
    @Environment(\.duovaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showsSplitter: Bool

    init(startInSplitter: Bool = false) {
        _showsSplitter = State(initialValue: startInSplitter)
    }

    @State private var query = ""
    @State private var searching = false
    @State private var showsProfile = false
    @State private var profileAtRoot = true
    @FocusState private var searchFocused: Bool
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.3, dampingFraction: 0.85)))
    private var dragOffset: CGFloat = 0

    var body: some View {
        Group {
            if showsSplitter {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        titleRow
                        SplitterView()
                    }
                    .padding(20)
                }
            } else {
                LibraryView(query: $query) { titleRow }
            }
        }
        .overlay { profilePanel }
        .onPreferenceChange(ProfileAtRootKey.self) { profileAtRoot = $0 }
    }

    // MARK: Title row

    /// "Apps" (or the search field while searching) with the navigation beside it.
    private var titleRow: some View {
        HStack(spacing: 8) {
            if searching {
                searchField
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
            } else {
                Text(showsSplitter ? "Splitter" : "Apps")
                    .font(.largeTitle.bold())
                    .foregroundStyle(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .transition(.opacity)
                Spacer(minLength: 0)
            }
            navigation
        }
        .frame(minHeight: 52)
    }

    /// Three separate glass buttons.
    private var navigation: some View {
        HStack(spacing: 6) {
            navButton("square.grid.2x2.fill", label: "Apps", isActive: !showsSplitter && !searching && !showsProfile) {
                endSearch()
                showsSplitter = false
                setProfile(shown: false)
            }
            navButton("rectangle.split.2x1", label: "Splitter", isActive: showsSplitter && !showsProfile) {
                endSearch()
                showsSplitter = true
                setProfile(shown: false)
            }
            navButton("person.crop.circle.fill", label: "Profile", isActive: showsProfile) {
                endSearch()
                setProfile(shown: true)
            }
            navButton(searching ? "xmark" : "magnifyingglass", label: searching ? "Close search" : "Search", isActive: searching) {
                if searching { endSearch() } else { beginSearch() }
            }
        }
    }

    private func navButton(
        _ symbol: String, label: LocalizedStringKey, isActive: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isActive ? theme.accent : theme.textPrimary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(
            isActive ? .regular.tint(theme.accent.opacity(0.22)).interactive() : .regular.interactive(),
            in: Circle()
        )
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: Search

    /// Takes the title's place while searching, so the keyboard never covers it.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(theme.textSecondary)
                .accessibilityHidden(true)

            TextField("Search apps", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit { searchFocused = false }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, query.isEmpty ? 16 : 4)
        .frame(height: 46)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    private func beginSearch() {
        showsSplitter = false
        setProfile(shown: false)
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.9)) {
            searching = true
        }
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            searchFocused = true
        }
    }

    private func endSearch() {
        guard searching else { return }
        searchFocused = false
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.9)) {
            searching = false
            query = ""
        }
    }

    // MARK: Profile panel

    /// Runs to the very right edge of the screen, like the apps do.
    private var profilePanel: some View {
        GeometryReader { geo in
            ZStack(alignment: .trailing) {
                if showsProfile {
                    // The apps stay visible but inactive; tapping them closes the panel.
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { setProfile(shown: false) }
                        .accessibilityLabel("Close profile")
                        .accessibilityAddTraits(.isButton)
                        .transition(.opacity)

                    ProfileView()
                        .frame(width: panelWidth(in: geo.size))
                        .shadow(color: .black.opacity(0.25), radius: 24, x: -6)
                        .offset(x: dragOffset)
                        .gesture(dismissDrag, isEnabled: profileAtRoot)
                        .accessibilityAction(.escape) { setProfile(shown: false) }
                        .transition(.move(edge: .trailing))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .trailing)
        }
        .ignoresSafeArea(.container, edges: .horizontal)
    }

    /// Half the screen in landscape, open or closed, so the panel stops at the
    /// middle; nearly the full width in portrait.
    private func panelWidth(in size: CGSize) -> CGFloat {
        if size.width > size.height {
            return size.width / 2
        }
        return min(size.width - 56, 560)
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 16)
            .updating($dragOffset) { value, state, _ in
                state = max(0, value.translation.width)
            }
            .onEnded { value in
                if value.translation.width > 90 || value.predictedEndTranslation.width > 240 {
                    setProfile(shown: false)
                }
            }
    }

    private func setProfile(shown: Bool) {
        guard showsProfile != shown else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.9)) {
            showsProfile = shown
        }
    }
}

/// Whether Profile is showing its first page, so swiping the panel away
/// never fights the navigation back-swipe on a deeper page.
struct ProfileAtRootKey: PreferenceKey {
    static let defaultValue = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value && nextValue()
    }
}
