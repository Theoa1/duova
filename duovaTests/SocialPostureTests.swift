import CoreGraphics
import Testing
@testable import duova

/// The seven layouts come from geometry and the system hinge status alone.
struct SocialPostureTests {
    private func input(_ w: CGFloat, _ h: CGFloat, hinge: HingeState = .unknown, companion: Bool = true,
                       layout: ExpandedLayout = .adaptive, ratio: PanelRatio = .sixtyForty) -> PostureInput {
        var input = PostureInput(size: CGSize(width: w, height: h))
        input.hinge = hinge
        input.companionWanted = companion
        input.layout = layout
        input.ratio = ratio
        return input
    }

    // MARK: Posture from signals

    @Test func closedPhone() {
        #expect(SocialPostureResolver.posture(for: input(393, 852)) == .closedPortrait)
        #expect(SocialPostureResolver.posture(for: input(852, 393)) == .closedLandscape)
        #expect(SocialPostureResolver.posture(for: input(393, 852, hinge: .closed)) == .closedPortrait)
    }

    @Test func fullyOpen() {
        #expect(SocialPostureResolver.posture(for: input(760, 820, hinge: .fullyOpen)) == .openPortrait)
        #expect(SocialPostureResolver.posture(for: input(820, 760, hinge: .fullyOpen)) == .openLandscape)
    }

    @Test func partlyOpen() {
        #expect(SocialPostureResolver.posture(for: input(820, 760, hinge: .partiallyOpen)) == .book)
        #expect(SocialPostureResolver.posture(for: input(760, 820, hinge: .partiallyOpen)) == .tabletop)
    }

    @Test func tentOnlyByOverride() {
        var tent = input(852, 393)
        tent.override = .tent
        let layout = SocialPostureResolver.resolve(tent)
        #expect(layout.posture == .tent)
        #expect(layout.companion == nil)
        #expect(layout.canShowCompanion == false)
    }

    // MARK: Single surface

    @Test func phoneIsAlwaysOneSurface() {
        for size in [(393.0, 852.0), (852.0, 393.0), (430.0, 932.0), (932.0, 430.0)] {
            let layout = SocialPostureResolver.resolve(input(size.0, size.1))
            #expect(layout.companion == nil)
            #expect(layout.canShowCompanion == false)
            #expect(layout.primary == CGRect(x: 0, y: 0, width: size.0, height: size.1))
        }
    }

    @Test func companionIsSuspendedNotShownWithoutContent() {
        let layout = SocialPostureResolver.resolve(input(1194, 834, companion: false))
        #expect(layout.canShowCompanion)
        #expect(layout.companion == nil)
        #expect(layout.primary.width == 1194)
    }

    @Test func singleLayoutPreferenceNeverSplits() {
        let layout = SocialPostureResolver.resolve(input(1194, 834, layout: .single))
        #expect(layout.companion == nil)
        #expect(layout.canShowCompanion == false)
    }

    // MARK: Two surfaces

    @Test func wideDisplaySplitsSixtyForty() {
        let layout = SocialPostureResolver.resolve(input(1194, 834))
        let companion = try! #require(layout.companion)
        #expect(layout.posture == .closedLandscape)
        #expect(layout.isVerticalSplit == false)
        #expect(layout.primary.width >= SocialPostureResolver.primaryMinimum)
        #expect(companion.width >= SocialPostureResolver.companionMinimum)
        #expect(abs(layout.primary.width / (layout.primary.width + companion.width) - 0.6) < 0.01)
        #expect(layout.primary.maxX + SocialPostureResolver.gutter == companion.minX)
        #expect(companion.maxX == 1194)
    }

    @Test func savedRatiosAreClampedToMinimumWidths() {
        // 70:30 of 820 would leave the companion at 246; it is clamped to 320.
        let layout = SocialPostureResolver.resolve(input(820, 760, ratio: .seventyThirty))
        let companion = try! #require(layout.companion)
        #expect(companion.width >= SocialPostureResolver.companionMinimum)
        #expect(layout.primary.width >= SocialPostureResolver.primaryMinimum)

        // 50:50 fits comfortably on a wide display.
        let even = SocialPostureResolver.resolve(input(1194, 834, ratio: .fiftyFifty))
        let evenCompanion = try! #require(even.companion)
        #expect(abs(even.primary.width - evenCompanion.width) <= SocialPostureResolver.gutter + 1)
    }

    @Test func adaptiveNeedsRoughly760Points() {
        #expect(SocialPostureResolver.resolve(input(740, 900)).canShowCompanion == false)
        #expect(SocialPostureResolver.resolve(input(760, 900)).canShowCompanion)
        // An explicit split preference only needs the minimum widths.
        #expect(SocialPostureResolver.resolve(input(740, 900, layout: .split)).canShowCompanion)
        #expect(SocialPostureResolver.resolve(input(700, 900, layout: .split)).canShowCompanion == false)
    }

    @Test func safeAreasReduceUsableWidth() {
        var narrow = input(770, 900)
        narrow.safeLeading = 20
        narrow.safeTrailing = 20
        #expect(SocialPostureResolver.resolve(narrow).canShowCompanion == false)
    }

    // MARK: Folded

    @Test func bookKeepsContentOffTheFold() {
        let layout = SocialPostureResolver.resolve(input(820, 760, hinge: .partiallyOpen))
        let companion = try! #require(layout.companion)
        let gap = try! #require(layout.foldGap)
        #expect(layout.posture == .book)
        #expect(layout.primary.maxX <= gap.minX)
        #expect(companion.minX >= gap.maxX)
        #expect(abs(gap.midX - 410) < 0.5)
    }

    @Test func tabletopStacksAroundTheFold() {
        let layout = SocialPostureResolver.resolve(input(760, 820, hinge: .partiallyOpen))
        let companion = try! #require(layout.companion)
        let gap = try! #require(layout.foldGap)
        #expect(layout.posture == .tabletop)
        #expect(layout.isVerticalSplit)
        #expect(layout.primary.maxY <= gap.minY)
        #expect(companion.minY >= gap.maxY)
        #expect(companion.maxY == 820)
        #expect(layout.primary.width == 760 && companion.width == 760)
    }

    @Test func tooSmallToFoldSplitStaysSingle() {
        // A small folded window can't give both halves their minimums.
        let layout = SocialPostureResolver.resolve(input(700, 500, hinge: .partiallyOpen))
        #expect(layout.posture == .book)
        #expect(layout.companion == nil)
    }
}
