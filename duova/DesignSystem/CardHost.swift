import SwiftUI

// MARK: - Closing

private struct CloseSheetKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    /// Closes the enclosing card, wherever it was opened from.
    var closeSheet: @MainActor () -> Void {
        get { self[CloseSheetKey.self] }
        set { self[CloseSheetKey.self] = newValue }
    }
}

/// Set by card content that shouldn't close at all right now (mid-save).
private struct CardCloseBlockedKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// Set by card content that keeps its X even when the phone is open.
private struct CardCloseButtonKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// Set by card content with unsaved changes: closing asks first.
private struct CardHasChangesKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

// MARK: - Stack

/// Every open card. One host draws them above the whole window, so a card
/// opened from a small row still gets its full size and never sits under
/// other content.
@Observable
private final class CardStack {
    struct Entry: Identifiable {
        let id: UUID
        /// The `morphSource` it grows out of, if any.
        var source: AnyHashable?
        /// Where it grows from and shrinks back to, in window coordinates.
        var anchor: CGRect
        var content: AnyView
        var close: @MainActor () -> Void
        var closeBlocked = false
        var hasChanges = false
        var wantsCloseButton = false
        /// Bumped when closing needs the person to confirm discarding changes.
        var discardRequests = 0
        var isClosing = false
    }

    private(set) var entries: [Entry] = []
    @ObservationIgnored private var anchors: [AnyHashable: CGRect] = [:]

    func anchor(for source: AnyHashable) -> CGRect? { anchors[source] }
    func setAnchor(_ frame: CGRect, for source: AnyHashable) { anchors[source] = frame }

    /// A source stays hidden while its card is open, and shows again as the
    /// card shrinks back into it.
    func isLifted(_ source: AnyHashable) -> Bool {
        entries.contains { $0.source == source && !$0.isClosing }
    }

    func present(_ entry: Entry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index].content = entry.content
            entries[index].close = entry.close
            entries[index].isClosing = false
        } else {
            entries.append(entry)
        }
    }

    /// Starts the card's shrink; it's removed when that finishes.
    func dismiss(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isClosing = true
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id && $0.isClosing }
    }

    func setCloseBlocked(_ blocked: Bool, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].closeBlocked != blocked else { return }
        entries[index].closeBlocked = blocked
    }

    func setHasChanges(_ changed: Bool, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].hasChanges != changed else { return }
        entries[index].hasChanges = changed
    }

    func setWantsCloseButton(_ wants: Bool, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].wantsCloseButton != wants else { return }
        entries[index].wantsCloseButton = wants
    }

    var hasOpenCard: Bool { entries.contains { !$0.isClosing } }

    /// A tap outside, the X or a swipe: closes the card, asks first if it has
    /// unsaved changes, and does nothing mid-save.
    func requestClose(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }), !entries[index].closeBlocked else { return }
        if entries[index].hasChanges {
            entries[index].discardRequests += 1
        } else {
            entries[index].close()
        }
    }

    func closeTop() {
        guard let top = entries.last(where: { !$0.isClosing }) else { return }
        requestClose(top.id)
    }
}

private struct CardStackKey: EnvironmentKey {
    static let defaultValue: CardStack? = nil
}

private extension EnvironmentValues {
    var cardStack: CardStack? {
        get { self[CardStackKey.self] }
        set { self[CardStackKey.self] = newValue }
    }
}

// MARK: - Host

private struct CardHost: ViewModifier {
    @Environment(\.bookPosture) private var book
    @Environment(\.duovaTheme) private var theme
    @State private var stack = CardStack()
    @State private var insets = EdgeInsets()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: EdgeInsets.self, of: { $0.safeAreaInsets }) { insets = $0 }
            .overlay {
                GeometryReader { geo in
                    let origin = geo.frame(in: .global).origin
                    ZStack(alignment: .topLeading) {
                        if stack.hasOpenCard {
                            Color.black.opacity(theme.isDark ? 0.45 : 0.25)
                                .onTapGesture { stack.closeTop() }
                                .accessibilityHidden(true)
                                .transition(.opacity)
                        }
                        ForEach(stack.entries) { entry in
                            let target = target(for: entry, origin: origin, size: geo.size)
                            MorphingCard(
                                entry: entry, stack: stack,
                                anchor: entry.anchor.offsetBy(dx: -origin.x, dy: -origin.y),
                                target: target, swipeEdge: swipeEdge(for: target, in: geo.size),
                                outer: outerCorners(for: target, in: geo.size),
                                showsCloseButton: book == nil || entry.wantsCloseButton)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .animation(.easeInOut(duration: 0.3), value: stack.hasOpenCard)
                }
                .ignoresSafeArea(.container)
            }
            .environment(\.cardStack, stack)
    }

    /// Cards sit a screen margin in from the edges, on the side of the screen
    /// they were opened from:
    /// - open, top and bottom: most of the height, from that edge;
    /// - landscape: a little over half the width, more when closed, full height;
    /// - closed portrait: everything below the status bar.
    private func target(for entry: CardStack.Entry, origin: CGPoint, size: CGSize) -> CGRect {
        let margin = DuovaMetrics.screenMargin
        let anchor = entry.anchor.offsetBy(dx: -origin.x, dy: -origin.y)
        let leading = max(margin, insets.leading)
        let trailing = max(margin, insets.trailing)
        let top = max(margin, insets.top)
        let bottom = margin
        let fullWidth = size.width - leading - trailing

        if book?.axis == .vertical {
            let height = min(size.height * 0.72, size.height - top - bottom)
            return anchor.midY < size.height / 2 - 1
                ? CGRect(x: leading, y: top, width: fullWidth, height: height)
                : CGRect(x: leading, y: size.height - bottom - height, width: fullWidth, height: height)
        }
        if size.width > size.height {
            let width = min(size.width * (book == nil ? 0.64 : 0.58), fullWidth)
            return anchor.midX < size.width / 2 - 1
                ? CGRect(x: leading, y: margin, width: width, height: size.height - margin - bottom)
                : CGRect(x: size.width - trailing - width, y: margin, width: width, height: size.height - margin - bottom)
        }
        let y = insets.top + 8
        return CGRect(x: leading, y: y, width: fullWidth, height: size.height - y - bottom)
    }

    /// The corners that sit against the screen's edge follow the display's
    /// rounding; the others stay small.
    private func outerCorners(for target: CGRect, in size: CGSize) -> CardCorners {
        if book?.axis == .vertical {
            return target.midY < size.height / 2 ? .top : .bottom
        }
        if size.width > size.height {
            return target.midX >= size.width / 2 ? .trailing : .leading
        }
        return .bottom
    }

    /// In landscape a card can be swiped back toward the edge it sits on.
    private func swipeEdge(for target: CGRect, in size: CGSize) -> HorizontalEdge? {
        guard size.width > size.height, book?.axis != .vertical else { return nil }
        return target.midX >= size.width / 2 ? .trailing : .leading
    }
}

private struct CardCorners: Equatable {
    var topLeading = false, topTrailing = false, bottomLeading = false, bottomTrailing = false

    static let top = CardCorners(topLeading: true, topTrailing: true)
    static let bottom = CardCorners(bottomLeading: true, bottomTrailing: true)
    static let leading = CardCorners(topLeading: true, bottomLeading: true)
    static let trailing = CardCorners(topTrailing: true, bottomTrailing: true)
}

/// Grows out of its anchor into place and shrinks back into it, like a
/// Pinterest pin. The content is laid out once at full size and scaled with
/// the card, so nothing reflows mid-animation. Corners near the screen's
/// corners follow the display's rounding; the inner ones stay small.
private struct MorphingCard: View {
    @Environment(\.duovaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let entry: CardStack.Entry
    let stack: CardStack
    let anchor: CGRect
    let target: CGRect
    let swipeEdge: HorizontalEdge?
    let outer: CardCorners
    let showsCloseButton: Bool

    @State private var progress: CGFloat = 0
    @State private var confirmDiscard = false
    @State private var surface: Double = 1
    @GestureState private var swipe: CGFloat = 0

    private var spring: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.46, dampingFraction: 0.86)
    }

    var body: some View {
        let start = anchor.width > 1 && anchor.height > 1 ? anchor : target.insetBy(dx: target.width * 0.06, dy: target.height * 0.06)
        let frame = CGRect(
            x: start.minX + (target.minX - start.minX) * progress,
            y: start.minY + (target.minY - start.minY) * progress,
            width: start.width + (target.width - start.width) * progress,
            height: start.height + (target.height - start.height) * progress)
        let outerStyle: Edge.Corner.Style = .concentric(minimum: .fixed(16 + 22 * progress))
        let innerStyle: Edge.Corner.Style = .fixed(16)
        let shape = ConcentricRectangle(
            topLeadingCorner: outer.topLeading ? outerStyle : innerStyle,
            topTrailingCorner: outer.topTrailing ? outerStyle : innerStyle,
            bottomLeadingCorner: outer.bottomLeading ? outerStyle : innerStyle,
            bottomTrailingCorner: outer.bottomTrailing ? outerStyle : innerStyle)

        ZStack(alignment: .topLeading) {
            DuovaBackdrop()
            entry.content
                .environment(\.closeSheet, entry.close)
                .background { DuovaBackdrop() }
                .onPreferenceChange(CardCloseBlockedKey.self) { stack.setCloseBlocked($0, for: entry.id) }
                .onPreferenceChange(CardHasChangesKey.self) { stack.setHasChanges($0, for: entry.id) }
                .onPreferenceChange(CardCloseButtonKey.self) { stack.setWantsCloseButton($0, for: entry.id) }
                .frame(width: target.width, height: target.height)
                .scaleEffect(frame.width / max(target.width, 1), anchor: .topLeading)
                .opacity(Double(progress))
                .allowsHitTesting(!entry.isClosing)
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .clipShape(shape)
        .overlay { shape.stroke(theme.border, lineWidth: 1) }
        .overlay(alignment: .topTrailing) {
            if showsCloseButton {
                Button { stack.requestClose(entry.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .padding(12)
                .opacity(Double(progress))
                .allowsHitTesting(!entry.isClosing)
                .accessibilityLabel("Close")
            }
        }
        .shadow(color: .black.opacity(0.3 * Double(progress)), radius: 24, y: 8)
        .opacity(surface)
        .position(x: frame.midX, y: frame.midY)
        .offset(x: swipe)
        .simultaneousGesture(swipeBack, isEnabled: swipeEdge != nil && !entry.isClosing)
        .accessibilityAddTraits(.isModal)
        .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { entry.close() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your changes aren't saved.")
        }
        .onChange(of: entry.discardRequests) { confirmDiscard = true }
        .onAppear {
            withAnimation(spring) { progress = 1 }
        }
        .onChange(of: entry.isClosing) { _, closing in
            if closing {
                withAnimation(.easeIn(duration: reduceMotion ? 0.2 : 0.38)) { surface = 0 }
                withAnimation(spring, completionCriteria: .logicallyComplete) {
                    progress = 0
                } completion: {
                    stack.remove(entry.id)
                }
            } else {
                withAnimation(spring) {
                    progress = 1
                    surface = 1
                }
            }
        }
    }
}

extension MorphingCard {
    /// Follows a sideways drag toward the card's edge and closes it past a
    /// short distance, unless it has unsaved changes.
    private var swipeBack: some Gesture {
        let direction: CGFloat = swipeEdge == .leading ? -1 : 1
        return DragGesture(minimumDistance: 24)
            .updating($swipe) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = max(0, value.translation.width * direction) * direction
            }
            .onEnded { value in
                let distance = value.translation.width * direction
                let predicted = value.predictedEndTranslation.width * direction
                guard abs(value.translation.width) > abs(value.translation.height),
                      distance > 120 || predicted > 280
                else { return }
                stack.requestClose(entry.id)
            }
    }
}

// MARK: - Presenting

private struct CardPresenter<Item: Identifiable, Card: View>: ViewModifier {
    @Environment(\.cardStack) private var stack
    @Binding var item: Item?
    let source: ((Item) -> AnyHashable)?
    let card: (Item) -> Card

    @State private var token = UUID()
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame = $0 }
            .onChange(of: item?.id, initial: true) { sync() }
            .onDisappear { stack?.dismiss(token) }
    }

    private func sync() {
        guard let stack else { return }
        guard let current = item else {
            stack.dismiss(token)
            return
        }
        let key = source?(current)
        let binding = $item
        stack.present(.init(
            id: token, source: key, anchor: key.flatMap(stack.anchor(for:)) ?? frame,
            content: AnyView(card(current)), close: { binding.wrappedValue = nil }))
    }
}

private struct MorphSourceModifier: ViewModifier {
    @Environment(\.cardStack) private var stack
    let key: AnyHashable

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { stack?.setAnchor($0, for: key) }
            .opacity(stack?.isLifted(key) == true ? 0 : 1)
            .animation(.easeOut(duration: 0.2), value: stack?.isLifted(key) == true)
    }
}

private struct CardFlag: Identifiable, Equatable {
    let id = 0
}

extension View {
    /// Opens `content` as a card that grows out of this view and shrinks back
    /// into it when closed.
    func pageSheet<Item: Identifiable, Sheet: View>(
        item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Sheet
    ) -> some View {
        modifier(CardPresenter(item: item, source: nil, card: content))
    }

    func pageSheet<Sheet: View>(
        isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Sheet
    ) -> some View {
        modifier(CardPresenter(item: flag(isPresented), source: nil, card: { _ in content() }))
    }

    /// Opens `content` as a card that grows out of the view marked
    /// `morphSource(source)`, such as the tapped tile, and back into it.
    func morphCard<Item: Identifiable, Card: View>(
        item: Binding<Item?>, from source: @escaping (Item) -> some Hashable,
        @ViewBuilder content: @escaping (Item) -> Card
    ) -> some View {
        modifier(CardPresenter(item: item, source: { AnyHashable(source($0)) }, card: content))
    }

    func morphCard<Card: View>(
        isPresented: Binding<Bool>, from source: some Hashable, @ViewBuilder content: @escaping () -> Card
    ) -> some View {
        let key = AnyHashable(source)
        return modifier(CardPresenter(item: flag(isPresented), source: { _ in key }, card: { _ in content() }))
    }

    /// The view a `morphCard` grows out of. It hides while its card is open.
    func morphSource(_ key: some Hashable) -> some View {
        modifier(MorphSourceModifier(key: AnyHashable(key)))
    }

    /// Where every card below draws itself. Put it once near the root, inside
    /// the environment the cards need.
    func pageSheetHost() -> some View {
        modifier(CardHost())
    }

    /// Keeps the enclosing card from closing at all, for example mid-save.
    func pageSheetCloseDisabled(_ disabled: Bool) -> some View {
        preference(key: CardCloseBlockedKey.self, value: disabled)
    }

    /// Keeps the enclosing card's X on an open phone too, where cards
    /// otherwise close only by a tap outside them.
    func cardCloseButton() -> some View {
        preference(key: CardCloseButtonKey.self, value: true)
    }

    /// Makes closing the enclosing card ask before throwing away unsaved changes.
    func cardDiscardGuard(_ hasChanges: Bool) -> some View {
        preference(key: CardHasChangesKey.self, value: hasChanges)
    }

    private func flag(_ isPresented: Binding<Bool>) -> Binding<CardFlag?> {
        Binding(
            get: { isPresented.wrappedValue ? CardFlag() : nil },
            set: { isPresented.wrappedValue = $0 != nil })
    }
}
