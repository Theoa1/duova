import CoreGraphics
import Foundation

/// The seven layout states. They are design states: which one applies comes
/// from the window's real geometry and the system hinge status, never from a
/// guess about hardware. Tent can't be told apart from the others by any
/// signal the system publishes, so it's reachable only through a developer
/// override and otherwise falls back to the closed layouts.
enum SocialPosture: String, Codable, CaseIterable {
    case closedPortrait, closedLandscape, openPortrait, openLandscape, book, tabletop, tent
}

/// What the system says about the hinge, if there is one.
enum HingeState: Equatable {
    case unknown, closed, partiallyOpen, fullyOpen
}

/// Everything the layout depends on, in points.
struct PostureInput: Equatable {
    var size: CGSize
    var safeTop: CGFloat = 0
    var safeLeading: CGFloat = 0
    var safeBottom: CGFloat = 0
    var safeTrailing: CGFloat = 0
    var hinge: HingeState = .unknown
    var layout: ExpandedLayout = .adaptive
    var ratio: PanelRatio = .sixtyForty
    /// The companion has something to show; without it the primary fills the window.
    var companionWanted = false
    var override: SocialPosture? = nil
}

/// Frames for the panes, in the host's coordinate space.
struct PostureLayout: Equatable {
    var posture: SocialPosture
    var primary: CGRect
    /// Nil when the companion is suspended (kept, not shown).
    var companion: CGRect?
    /// Where the physical fold is assumed to be; nothing is laid out across it.
    var foldGap: CGRect?
    /// Geometry allows a second pane right now, whether or not one is showing.
    var canShowCompanion: Bool
    /// The split is top/bottom (tabletop) rather than side by side.
    var isVerticalSplit: Bool
}

/// Turns geometry into one of the seven layouts.
///
/// Two panes need room: about 760 pt of usable width in adaptive mode, and in
/// every mode at least ~390 pt for the primary and ~320 pt for the companion
/// after the gutter. Ratios are clamped to those minimums rather than clipping
/// content. The same rules apply vertically for the tabletop split.
///
/// The keyboard doesn't change the frames: each web view insets its own
/// content for it, so the pane that has focus stays where it is and scrolls
/// its field into view, which is what a person typing expects.
enum SocialPostureResolver {
    static let adaptiveTwoPaneMinimum: CGFloat = 760
    static let primaryMinimum: CGFloat = 390
    static let companionMinimum: CGFloat = 320
    /// Hairline between panes on a flat display.
    static let gutter: CGFloat = 1
    /// Clearance left around a partly open hinge.
    static let foldClearance: CGFloat = 24

    static func posture(for input: PostureInput) -> SocialPosture {
        if let override = input.override { return override }
        let landscape = input.size.width >= input.size.height
        switch input.hinge {
        case .fullyOpen: return landscape ? .openLandscape : .openPortrait
        case .partiallyOpen: return landscape ? .book : .tabletop
        case .closed, .unknown: return landscape ? .closedLandscape : .closedPortrait
        }
    }

    static func resolve(_ input: PostureInput) -> PostureLayout {
        let posture = posture(for: input)
        let bounds = CGRect(origin: .zero, size: input.size)
        let usable = CGRect(
            x: input.safeLeading, y: input.safeTop,
            width: max(0, input.size.width - input.safeLeading - input.safeTrailing),
            height: max(0, input.size.height - input.safeTop - input.safeBottom))
        let folded = posture == .book || posture == .tabletop
        let vertical = posture == .tabletop

        // The fold runs through the middle of the longer side.
        var foldGap: CGRect?
        if folded {
            foldGap = vertical
                ? CGRect(x: 0, y: bounds.midY - foldClearance / 2, width: bounds.width, height: foldClearance)
                : CGRect(x: bounds.midX - foldClearance / 2, y: 0, width: foldClearance, height: bounds.height)
        }

        let along = vertical ? usable.height : usable.width
        let separator = folded ? foldClearance : gutter
        let fits: Bool = {
            switch input.layout {
            case .single: return false
            case .split: return along - separator >= primaryMinimum + companionMinimum
            case .adaptive:
                return along >= (vertical ? primaryMinimum + companionMinimum + separator : adaptiveTwoPaneMinimum)
                    && along - separator >= primaryMinimum + companionMinimum
            }
        }()
        // Tent and a closed phone never split; a closed display that is wide
        // enough (iPad) may.
        let canShowCompanion = fits && posture != .tent

        guard canShowCompanion, input.companionWanted else {
            // One surface. Keep it off a partly open fold's clearance only
            // when the fold is vertical in a book; across a tabletop fold a
            // single surface is still usable, so it fills the window.
            return PostureLayout(
                posture: posture, primary: bounds, companion: nil, foldGap: foldGap,
                canShowCompanion: canShowCompanion, isVerticalSplit: vertical)
        }

        let available = along - separator
        var primaryLength: CGFloat
        if folded {
            // Pages are the two halves; the fold decides the split.
            primaryLength = (along - separator) / 2
        } else {
            primaryLength = (available * input.ratio.fraction).rounded()
        }
        primaryLength = min(max(primaryLength, primaryMinimum), available - companionMinimum)

        if vertical {
            // Primary on top, companion below (the half nearer the keyboard).
            let primary = CGRect(x: 0, y: 0, width: bounds.width, height: usable.minY + primaryLength)
            let companionTop = primary.maxY + separator
            let companion = CGRect(
                x: 0, y: companionTop, width: bounds.width, height: max(0, bounds.height - companionTop))
            return PostureLayout(
                posture: posture, primary: primary, companion: companion, foldGap: foldGap,
                canShowCompanion: true, isVerticalSplit: true)
        }
        // Primary on the leading side, companion on the trailing side.
        let primary = CGRect(x: 0, y: 0, width: usable.minX + primaryLength, height: bounds.height)
        let companionLeft = primary.maxX + separator
        let companion = CGRect(x: companionLeft, y: 0, width: max(0, bounds.width - companionLeft), height: bounds.height)
        return PostureLayout(
            posture: posture, primary: primary, companion: companion, foldGap: foldGap,
            canShowCompanion: true, isVerticalSplit: false)
    }
}

extension PanelRatio {
    var fraction: CGFloat {
        switch self {
        case .fiftyFifty: 0.5
        case .sixtyForty: 0.6
        case .seventyThirty: 0.7
        }
    }
}
