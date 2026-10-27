import CoreGraphics
import Testing
@testable import duova

struct SocialPostureTests {
    private func input(_ w: CGFloat, _ h: CGFloat, hinge: HingeState = .unknown,
                       companion: Bool = true, layout: ExpandedLayout = .adaptive,
                       ratio: PanelRatio = .sixtyForty) -> PostureInput {
        var input = PostureInput(size: CGSize(width: w, height: h))
        input.hinge = hinge
        input.companionWanted = companion
        input.layout = layout
        input.ratio = ratio
        return input
    }

    @Test func postureUsesHingeAndRealDivision() {
        #expect(SocialPostureResolver.posture(for: input(393, 852)) == .closedPortrait)
        #expect(SocialPostureResolver.posture(for: input(852, 393, hinge: .closed)) == .closedLandscape)
        #expect(SocialPostureResolver.posture(for: input(760, 820, hinge: .fullyOpen)) == .openPortrait)
        #expect(SocialPostureResolver.posture(for: input(820, 760, hinge: .fullyOpen)) == .openLandscape)
        var book = input(820, 760, hinge: .partiallyOpen)
        book.divisionRegion = CGRect(x: 398, y: 0, width: 24, height: 760)
        #expect(SocialPostureResolver.posture(for: book) == .book)
        var tabletop = input(760, 820, hinge: .partiallyOpen)
        tabletop.divisionRegion = CGRect(x: 0, y: 398, width: 760, height: 24)
        #expect(SocialPostureResolver.posture(for: tabletop) == .tabletop)
        #expect(SocialPostureResolver.posture(for: input(820, 760, hinge: .partiallyOpen)) == .closedLandscape)
    }

    @Test func onlyOpenLandscapeAllowsCompanionEvenWithExplicitSplit() {
        for posture in SocialPosture.allCases {
            var request = input(1194, 834, layout: .split)
            request.override = posture
            let result = SocialPostureResolver.resolve(request)
            #expect(result.canShowCompanion == (posture == .openLandscape))
            #expect((result.companion != nil) == (posture == .openLandscape))
        }
    }

    @Test func closedAndUnknownDisplaysNeverSplitRegardlessOfWidth() {
        for hinge in [HingeState.closed, .unknown] {
            for size in [(393.0, 852.0), (852.0, 393.0), (1194.0, 834.0)] {
                let result = SocialPostureResolver.resolve(input(size.0, size.1, hinge: hinge, layout: .split))
                #expect(result.companion == nil)
                #expect(!result.canShowCompanion)
                #expect(result.primary == CGRect(x: 0, y: 0, width: size.0, height: size.1))
            }
        }
    }

    @Test func openPortraitKeepsWholeSingleSurface() {
        let result = SocialPostureResolver.resolve(input(834, 1194, hinge: .fullyOpen, layout: .split))
        #expect(result.companion == nil)
        #expect(!result.canShowCompanion)
        #expect(result.primary == CGRect(x: 0, y: 0, width: 834, height: 1194))
    }

    @Test func unusedCompanionDoesNotReducePrimary() {
        let result = SocialPostureResolver.resolve(input(1194, 834, hinge: .fullyOpen, companion: false))
        #expect(result.canShowCompanion)
        #expect(result.companion == nil)
        #expect(result.primary.width == 1194)
    }

    @Test func singlePreferenceNeverSplits() {
        let result = SocialPostureResolver.resolve(input(1194, 834, hinge: .fullyOpen, layout: .single))
        #expect(result.companion == nil)
        #expect(!result.canShowCompanion)
    }

    @Test func openLandscapeUsesSavedRatioAndSpacing() throws {
        let result = SocialPostureResolver.resolve(input(1194, 834, hinge: .fullyOpen))
        let companion = try #require(result.companion)
        #expect(result.posture == .openLandscape)
        #expect(!result.isVerticalSplit)
        #expect(abs(result.primary.width / (result.primary.width + companion.width) - 0.6) < 0.01)
        #expect(companion.minX - result.primary.maxX == 8)
        #expect(companion.maxX == 1194)
    }

    @Test func ratiosRespectMinimumWidths() throws {
        let result = SocialPostureResolver.resolve(input(820, 760, hinge: .fullyOpen, ratio: .seventyThirty))
        let companion = try #require(result.companion)
        #expect(companion.width >= SocialPostureResolver.companionMinimum)
        #expect(result.primary.width >= SocialPostureResolver.primaryMinimum)
    }

    @Test func widthAndSafeAreaStillConstrainOpenLandscape() {
        #expect(!SocialPostureResolver.resolve(input(740, 600, hinge: .fullyOpen)).canShowCompanion)
        #expect(SocialPostureResolver.resolve(input(760, 600, hinge: .fullyOpen)).canShowCompanion)
        #expect(SocialPostureResolver.resolve(input(740, 600, hinge: .fullyOpen, layout: .split)).canShowCompanion)
        #expect(!SocialPostureResolver.resolve(input(700, 600, hinge: .fullyOpen, layout: .split)).canShowCompanion)
        var narrow = input(770, 600, hinge: .fullyOpen)
        narrow.safeLeading = 30
        narrow.safeTrailing = 10
        #expect(!SocialPostureResolver.resolve(narrow).canShowCompanion)
    }

    @Test func foldedSingleSurfaceAvoidsActualDivision() throws {
        for vertical in [false, true] {
            var request = input(vertical ? 760 : 820, vertical ? 820 : 760, hinge: .partiallyOpen, layout: .split)
            request.divisionRegion = vertical
                ? CGRect(x: 0, y: 398, width: 760, height: 24)
                : CGRect(x: 398, y: 0, width: 24, height: 760)
            let result = SocialPostureResolver.resolve(request)
            let gap = try #require(result.foldGap)
            #expect(result.posture == (vertical ? .tabletop : .book))
            #expect(!result.canShowCompanion)
            #expect(result.companion == nil)
            #expect(result.primary.intersection(gap).isEmpty)
        }
    }
}
