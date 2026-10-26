import SwiftUI
import UIKit

/// The signed-in app.
///
/// Navigation always lives on the right edge, as three separate liquid-glass
/// buttons: Apps, Profile and Search. Where the system provides its vertical bar
/// on the right, the buttons sit inside that space; anywhere it doesn't (for
/// example in landscape), Duova keeps an equivalent strip on the right so the
/// buttons never move. Nothing sits on the content itself.
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
    @Environment(\.bookPosture) private var book

    @State private var query = ""
    @State private var searching = false
    @State private var showsProfile = false
    @State private var profileAtRoot = true
    @State private var systemBarOnTrailing = false
    @State private var cameraOnTrailing = false
    @State private var trailingInset: CGFloat = 0
    @FocusState private var searchFocused: Bool
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.3, dampingFraction: 0.85)))
    private var dragOffset: CGFloat = 0

    /// Width of Duova's own strip when the system has no vertical bar on the right.
    private let stripWidth: CGFloat = 68

    /// The system's vertical bar is on the right and has room for the buttons.
    private var usesSystemBar: Bool { systemBarOnTrailing && trailingInset >= 44 }

    /// How far the navigation reaches in from the right edge of the screen.
    private var navigationAreaWidth: CGFloat {
        usesSystemBar ? trailingInset : trailingInset + stripWidth
    }

    var body: some View {
        // The apps stay full screen; the navigation floats over their right edge.
        LibraryView(query: $query)
            .environment(\.navigationAreaWidth, navigationAreaWidth)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if searching { searchField }
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.trailing }) { trailingInset = $0 }
            .overlay {
                if usesSystemBar {
                    navigation
                        .frame(width: trailingInset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .ignoresSafeArea(.container, edges: .trailing)
                } else {
                    navigation
                        .frame(width: stripWidth)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                }
            }
            .overlay { profilePanel }
            .onPreferenceChange(ProfileAtRootKey.self) { profileAtRoot = $0 }
            .background {
                ScreenEdgeReader { reading in
                    systemBarOnTrailing = reading.barOnTrailing
                    cameraOnTrailing = reading.cameraOnTrailing
                }
                .allowsHitTesting(false)
            }
    }

    // MARK: Navigation

    /// Three separate glass buttons, stacked at the bottom of the right edge.
    private var navigation: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            navButton("square.grid.2x2.fill", label: "Apps", isActive: !searching && !showsProfile) {
                endSearch()
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
        // A closed device turned clockwise has its front camera on the right,
        // beside the lowest button, so the buttons sit higher there.
        .padding(.bottom, book == nil && cameraOnTrailing ? 30 : 8)
        .frame(maxWidth: .infinity)
    }

    private func navButton(
        _ symbol: String, label: LocalizedStringKey, isActive: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(isActive ? theme.accent : theme.textPrimary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 48, height: 48)
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

    /// Shown only while searching, at the bottom of the apps, beside the Search button.
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
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, query.isEmpty ? 16 : 6)
        .frame(height: 52)
        .glassEffect(.regular.interactive(), in: Capsule())
        .padding(.leading, DuovaMetrics.screenMargin)
        // Stops beside the navigation buttons rather than under them.
        .padding(.trailing, usesSystemBar ? DuovaMetrics.screenMargin : stripWidth)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func beginSearch() {
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

    /// Runs to the very right edge of the screen, over the navigation, like the apps do.
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

extension EnvironmentValues {
    /// How far Duova's navigation buttons reach in from the right edge of the
    /// screen, so full-screen content can keep its own controls clear of them.
    @Entry var navigationAreaWidth: CGFloat = 0
}

/// Whether Profile is showing its first page, so swiping the panel away
/// never fights the navigation back-swipe on a deeper page.
struct ProfileAtRootKey: PreferenceKey {
    static let defaultValue = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value && nextValue()
    }
}

/// Reports what sits on the right edge of the screen: the system's vertical
/// bar, and (in landscape) the front camera.
private struct ScreenEdgeReader: UIViewRepresentable {
    struct Reading: Equatable {
        var barOnTrailing = false
        var cameraOnTrailing = false
    }

    let onChange: (Reading) -> Void

    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: ReaderView, context: Context) {
        uiView.onChange = onChange
    }

    final class ReaderView: UIView {
        var onChange: ((Reading) -> Void)?
        private var last: Reading?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            if #available(iOS 27.1, *) {
                registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) { (view: ReaderView, _) in
                    view.report()
                }
            }
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        /// Rotation resizes this view, so a new layout is when to check the orientation.
        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        private func report() {
            var reading = Reading()
            if #available(iOS 27.1, *) {
                reading.barOnTrailing = traitCollection.verticalBarEdge == .trailing
            }
            // Turned clockwise, the top of the device (and its front camera)
            // is on the right; iOS calls that interface orientation landscapeLeft.
            reading.cameraOnTrailing = window?.windowScene?.effectiveGeometry.interfaceOrientation == .landscapeLeft
            guard reading != last else { return }
            last = reading
            // Never change SwiftUI state in the middle of a layout pass.
            DispatchQueue.main.async { [onChange] in onChange?(reading) }
        }
    }
}
