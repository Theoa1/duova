import SwiftUI
import UIKit

// MARK: - Posture

/// The window is on a device whose hinge is open (a "book" arrangement).
///
/// The system reports only whether the hinge is closed, partially open or fully
/// open, never where the fold sits, so Duova does not guess at geometry. It
/// splits the window into two equal pages along its longer side: left and right
/// in a landscape window, top and bottom in a portrait one. Nothing is drawn
/// across the seam.
struct BookPosture: Equatable {
    /// The direction the two pages are laid out in. `.horizontal` = side by side.
    var axis: Axis
}

private struct BookPostureKey: EnvironmentKey {
    static let defaultValue: BookPosture? = nil
}

extension EnvironmentValues {
    /// Non-nil when the window should be laid out as two pages.
    var bookPosture: BookPosture? {
        get { self[BookPostureKey.self] }
        set { self[BookPostureKey.self] = newValue }
    }
}

// MARK: - Hinge monitoring

/// Tracks the system-reported hinge state. On devices without a hinge it never
/// reports anything and stays `false`.
@Observable
final class HingeMonitor {
    private(set) var isOpen = false

    func update(open: Bool) {
        if isOpen != open { isOpen = open }
    }
}

/// Invisible view that attaches the system hinge interaction.
private struct HingeReader: UIViewRepresentable {
    let monitor: HingeMonitor

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        if #available(iOS 27.1, *) {
            let monitor = monitor
            let interaction = UIHingeInteraction { _, update in
                guard let hinge = update.hinge else {
                    monitor.update(open: false)
                    return
                }
                monitor.update(open: hinge.status == .partiallyOpen || hinge.status == .fullyOpen)
            }
            view.addInteraction(interaction)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Publishes `bookPosture` to everything inside it.
private struct BookPostureProvider: ViewModifier {
    @State private var monitor = HingeMonitor()
    @State private var size: CGSize = .zero

    private var posture: BookPosture? {
        guard monitor.isOpen, size.width > 0, size.height > 0 else { return nil }
        // Split the longer side, so each page stays close to a phone-sized page.
        return BookPosture(axis: size.width >= size.height ? .horizontal : .vertical)
    }

    func body(content: Content) -> some View {
        content
            .environment(\.bookPosture, posture)
            .background {
                // Measures the whole window, keyboard included, so the posture
                // never flips (and rebuilds the screen) when the keyboard opens.
                Color.clear
                    .ignoresSafeArea()
                    .onGeometryChange(for: CGSize.self, of: { $0.size }) { size = $0 }
            }
            .background { HingeReader(monitor: monitor).allowsHitTesting(false) }
    }
}

extension View {
    /// Makes the hinge-driven `bookPosture` available to this view tree.
    func bookPostureAware() -> some View {
        modifier(BookPostureProvider())
    }
}

// MARK: - Two pages

/// Lays out two pages of equal size, split down the middle with no divider.
///
/// Pages extend to the outer edges of the window and keep their own safe-area
/// padding on the outer sides only, so nothing sits against the seam except the
/// page edge itself, and a page's content never crosses it.
struct BookSplit<First: View, Second: View>: View {
    let axis: Axis
    let first: First
    let second: Second

    init(axis: Axis, @ViewBuilder first: () -> First, @ViewBuilder second: () -> Second) {
        self.axis = axis
        self.first = first()
        self.second = second()
    }

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let fullWidth = geo.size.width + insets.leading + insets.trailing
            let fullHeight = geo.size.height + insets.top + insets.bottom

            Group {
                if axis == .horizontal {
                    HStack(spacing: 0) {
                        first
                            .safeAreaPadding(.leading, insets.leading)
                            .frame(width: fullWidth / 2, height: geo.size.height)
                        second
                            .safeAreaPadding(.trailing, insets.trailing)
                            .frame(width: fullWidth / 2, height: geo.size.height)
                    }
                    .frame(width: fullWidth, height: geo.size.height)
                    // Ignoring the side safe areas already moves the pair out to the
                    // screen edges; shifting it again would leave a bar on one side.
                    .ignoresSafeArea(.container, edges: .horizontal)
                } else {
                    VStack(spacing: 0) {
                        first
                            .safeAreaPadding(.top, insets.top)
                            .frame(width: geo.size.width, height: fullHeight / 2)
                        second
                            .safeAreaPadding(.bottom, insets.bottom)
                            .frame(width: geo.size.width, height: fullHeight / 2)
                    }
                    .frame(width: geo.size.width, height: fullHeight)
                    .ignoresSafeArea(.container, edges: .vertical)
                }
            }
        }
    }
}

// MARK: - Sheets that stay on their own page

private struct CloseSheetKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    /// Closes the enclosing `pageSheet`, wherever it is presented.
    var closeSheet: @MainActor () -> Void {
        get { self[CloseSheetKey.self] }
        set { self[CloseSheetKey.self] = newValue }
    }
}

/// Hands a system sheet's dismiss action to its content as `closeSheet`.
private struct SheetHost<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let content: Content

    var body: some View {
        content.environment(\.closeSheet, { dismiss() })
    }
}

/// A card that fills the page it was presented from.
private struct PageSheetCard<Content: View>: View {
    @Environment(\.duovaTheme) private var theme
    let close: () -> Void
    let content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(theme.isDark ? 0.45 : 0.25)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
                .accessibilityHidden(true)

            content
                .environment(\.closeSheet, close)
                .background { DuovaBackdrop() }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: 1)
                )
                .padding(8)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .accessibilityAddTraits(.isModal)
    }
}

private struct PageSheetModifier<Item: Identifiable, Sheet: View>: ViewModifier {
    @Environment(\.bookPosture) private var book
    @Binding var item: Item?
    let resizable: Bool
    let sheet: (Item) -> Sheet

    func body(content: Content) -> some View {
        if book != nil {
            content
                .overlay {
                    if let current = item {
                        PageSheetCard(close: { item = nil }, content: sheet(current))
                            .zIndex(1)
                    }
                }
                .animation(.easeInOut(duration: 0.28), value: item?.id)
        } else {
            content.sheet(item: $item) { current in
                if resizable {
                    SheetHost(content: sheet(current))
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                } else {
                    SheetHost(content: sheet(current))
                        .presentationSizing(.form)
                }
            }
        }
    }
}

private struct PageSheetFlag: Identifiable, Equatable {
    let id = 0
}

extension View {
    /// Presents `content` as a normal sheet, or, in a book arrangement, as a card
    /// inside this view's own page so it never straddles the seam.
    func pageSheet<Item: Identifiable, Sheet: View>(
        item: Binding<Item?>, resizable: Bool = false, @ViewBuilder content: @escaping (Item) -> Sheet
    ) -> some View {
        modifier(PageSheetModifier(item: item, resizable: resizable, sheet: content))
    }

    func pageSheet<Sheet: View>(
        isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Sheet
    ) -> some View {
        let flag = Binding<PageSheetFlag?>(
            get: { isPresented.wrappedValue ? PageSheetFlag() : nil },
            set: { isPresented.wrappedValue = $0 != nil }
        )
        return modifier(PageSheetModifier(item: flag, resizable: false, sheet: { _ in content() }))
    }
}
