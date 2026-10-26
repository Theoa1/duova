import SwiftUI

/// The shared full-screen frame for sign in and the lock screen. No cards or
/// sheets: just the Duova mark and the controls, on the app backdrop.
///
/// - **Portrait:** the controls sit low on the screen, within thumb's reach,
///   running nearly edge to edge. The brand appears here only when
///   `brandInPortrait` is set.
/// - **Landscape:** brand on one half, controls on the other.
/// - **Book arrangement:** the same two halves, one per page.
///
/// The controls live in a scroll view and receive its `ScrollViewProxy`, so a
/// focused field can always be scrolled above the keyboard.
struct AuthScaffold<Brand: View, Panel: View>: View {
    @Environment(\.bookPosture) private var book
    @State private var windowSize: CGSize = .zero

    private let brand: Brand
    private let brandInPortrait: Bool
    private let panel: (ScrollViewProxy) -> Panel

    /// Gap between the controls and the screen edges.
    private let edgeMargin: CGFloat = 12

    init(
        brandInPortrait: Bool = true,
        @ViewBuilder brand: () -> Brand,
        @ViewBuilder panel: @escaping (ScrollViewProxy) -> Panel
    ) {
        self.brandInPortrait = brandInPortrait
        self.brand = brand()
        self.panel = panel
    }

    var body: some View {
        GeometryReader { geo in
            // Orientation comes from the whole window, never the keyboard-reduced
            // area, so opening the keyboard can't swap the layout mid-typing.
            let stable = windowSize == .zero ? geo.size : windowSize
            let isLandscape = stable.width > stable.height * 1.1
            ZStack {
                DuovaBackdrop()
                if let book {
                    BookSplit(axis: book.axis) {
                        brandPage
                    } second: {
                        panelPage
                    }
                } else if isLandscape {
                    HStack(spacing: 0) {
                        brandPage
                        panelPage
                    }
                } else {
                    portrait(height: geo.size.height)
                }
            }
            .background {
                Color.clear
                    .ignoresSafeArea()
                    .onGeometryChange(for: CGSize.self, of: { $0.size }) { windowSize = $0 }
            }
        }
    }

    private var brandPage: some View {
        brand.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var panelPage: some View {
        GeometryReader { page in
            ScrollViewReader { proxy in
                ScrollView {
                    panel(proxy)
                        .frame(maxWidth: 520)
                        .padding(.horizontal, edgeMargin)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, minHeight: page.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
            }
        }
    }

    private func portrait(height: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 16)
                    if brandInPortrait {
                        brand
                        Spacer(minLength: 16)
                    }
                    panel(proxy)
                        .frame(maxWidth: 520)
                        .padding(.horizontal, edgeMargin)
                        .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity, minHeight: height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
        }
    }
}

/// The Duova mark on its own. The launch screen already introduced the name.
struct AuthBrand: View {
    @Environment(\.duovaTheme) private var theme
    var markSize: CGFloat = 72

    var body: some View {
        DuovaMark(style: theme.markStyle)
            .frame(width: markSize, height: markSize)
            .accessibilityLabel(Text("Duova"))
    }
}

extension View {
    /// Scrolls `id` into view shortly after the keyboard starts to appear.
    func revealOnFocus<Value: Hashable>(
        _ focus: FocusState<Value?>.Binding, in proxy: ScrollViewProxy, id: some Hashable
    ) -> some View {
        onChange(of: focus.wrappedValue) { _, newValue in
            guard newValue != nil else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(320))
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    func revealOnFocus(_ focus: FocusState<Bool>.Binding, in proxy: ScrollViewProxy, id: some Hashable) -> some View {
        onChange(of: focus.wrappedValue) { _, newValue in
            guard newValue else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(320))
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }
}
