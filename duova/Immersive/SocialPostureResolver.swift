import CoreGraphics
import Foundation

/// The seven layout states. They are design states: which one applies comes
/// from the window's real geometry and the system hinge status, never from a
/// guess about hardware. The SDK exposes hinge status/angle, not a physical
/// tent/standing classifier. That design state uses the compact production
/// fallback and remains explicitly selectable in layout simulations.
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
    /// Active system division region in this host's coordinates, margins included.
    var divisionRegion: CGRect? = nil
    var accessibilityLayout = false
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
    /// System division (or explicit simulated fold); panes never cross this frame.
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
/// content. Only the fully open landscape posture permits a companion.
///
/// The keyboard doesn't change the frames: each web view insets its own
/// content for it, so the pane that has focus stays where it is and scrolls
/// its field into view, which is what a person typing expects.
enum SocialPostureResolver {
    static let adaptiveTwoPaneMinimum: CGFloat = 760
    static let primaryMinimum: CGFloat = 390
    static let companionMinimum: CGFloat = 320
    /// Empty spacing between panes; the host does not draw a divider.
    static let gutter: CGFloat = 8
    /// Clearance left around a partly open hinge.
    static let foldClearance: CGFloat = 24

    static func posture(for input: PostureInput) -> SocialPosture {
        if let override = input.override { return override }
        let landscape = input.size.width >= input.size.height
        switch input.hinge {
        case .fullyOpen: return landscape ? .openLandscape : .openPortrait
        case .partiallyOpen:
            if let division = input.divisionRegion {
                return division.width >= division.height ? .tabletop : .book
            }
            // Without a region, use a responsive layout, never invent a fold.
            return landscape ? .closedLandscape : .closedPortrait
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
        let simulatedFold = input.override == .book || input.override == .tabletop
        let suppliedDivision = input.divisionRegion?.intersection(bounds)
        var foldGap = suppliedDivision.flatMap { $0.isNull || $0.isEmpty ? nil : $0 }
        if foldGap == nil, simulatedFold {
            // Only deterministic preview/test inputs may manufacture a center fold.
            foldGap = posture == .tabletop
                ? CGRect(x: 0, y: bounds.midY - foldClearance / 2, width: bounds.width, height: foldClearance)
                : CGRect(x: bounds.midX - foldClearance / 2, y: 0, width: foldClearance, height: bounds.height)
        }
        let vertical = foldGap.map { $0.width >= $0.height } ?? (posture == .tabletop)
        let minimumPrimary = primaryMinimum * (input.accessibilityLayout ? 1.25 : 1)
        let minimumCompanion = companionMinimum * (input.accessibilityLayout ? 1.25 : 1)

        if let gap = foldGap {
            // A physical division fixes the pane boundary. Never clamp a ratio
            // across it, even when safe areas on the two sides are asymmetric.
            let first = vertical
                ? CGRect(x: 0, y: 0, width: bounds.width, height: gap.minY)
                : CGRect(x: 0, y: 0, width: gap.minX, height: bounds.height)
            let second = vertical
                ? CGRect(x: 0, y: gap.maxY, width: bounds.width, height: max(0, bounds.maxY - gap.maxY))
                : CGRect(x: gap.maxX, y: 0, width: max(0, bounds.maxX - gap.maxX), height: bounds.height)
            let firstUsable = first.intersection(usable)
            let secondUsable = second.intersection(usable)
            let firstLength = firstUsable.isNull ? 0 : (vertical ? firstUsable.height : firstUsable.width)
            let secondLength = secondUsable.isNull ? 0 : (vertical ? secondUsable.height : secondUsable.width)
            let fits = input.layout != .single && posture == .openLandscape
                && firstLength >= minimumPrimary && secondLength >= minimumCompanion
                && (input.layout != .adaptive || vertical || usable.width >= adaptiveTwoPaneMinimum)
            let primaryFrame = fits && input.companionWanted ? first
                : (firstLength >= secondLength ? first : second)
            return PostureLayout(
                posture: posture, primary: primaryFrame,
                companion: fits && input.companionWanted ? second : nil, foldGap: gap,
                canShowCompanion: fits, isVerticalSplit: vertical)
        }

        let along = usable.width
        let fits = input.layout != .single && posture == .openLandscape
            && along - gutter >= minimumPrimary + minimumCompanion
            && (input.layout != .adaptive || along >= adaptiveTwoPaneMinimum)
        guard fits, input.companionWanted else {
            return PostureLayout(
                posture: posture, primary: bounds, companion: nil, foldGap: nil,
                canShowCompanion: fits, isVerticalSplit: false)
        }
        let available = along - gutter
        let primaryLength = min(
            max((available * input.ratio.fraction).rounded(), minimumPrimary),
            available - minimumCompanion)
        let primary = CGRect(x: 0, y: 0, width: usable.minX + primaryLength, height: bounds.height)
        let companionLeft = primary.maxX + gutter
        let companion = CGRect(x: companionLeft, y: 0, width: max(0, bounds.width - companionLeft), height: bounds.height)
        return PostureLayout(
            posture: posture, primary: primary, companion: companion, foldGap: nil,
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
