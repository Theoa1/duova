import SwiftUI

/// Responsive layout for the launch scene, derived only from the actual
/// container size and safe-area insets (never from a device name), so the same
/// code serves portrait, landscape, split scenes, iPad, and foldable shapes.
struct LaunchGeometry {
    /// Full container size, including the areas under system bars.
    let size: CGSize
    let insets: EdgeInsets

    /// Uniform scale applied to the hero icon, text, and spacing.
    let scale: CGFloat
    /// Center of the safe area.
    let mid: CGPoint
    let heroSize: CGFloat
    let heroCenter: CGPoint
    let tileSize: CGFloat
    /// Top edge of the wordmark/tagline block.
    let textTop: CGFloat
    let safeWidth: CGFloat
    let safeHeight: CGFloat

    private let radiusX: CGFloat
    private let radiusY: CGFloat

    /// Reserved height for wordmark + tagline (at the default text size).
    static let baseTextBlock: CGFloat = 74
    static let baseGap: CGFloat = 24

    init(size: CGSize, insets: EdgeInsets) {
        self.size = size
        self.insets = insets

        let safeW = max(1, size.width - insets.leading - insets.trailing)
        let safeH = max(1, size.height - insets.top - insets.bottom)
        let s = Motion.clamp(min(safeW / 390, safeH / 470), 0.62, 1.9)

        safeWidth = safeW
        safeHeight = safeH
        scale = s
        mid = CGPoint(x: insets.leading + safeW / 2, y: insets.top + safeH / 2)
        let hero = 112 * s
        heroSize = hero
        let tile = Motion.clamp(min(safeW, safeH) * 0.16, 40, 92)
        tileSize = tile

        let textBlock = Self.baseTextBlock * s
        let gap = Self.baseGap * s
        heroCenter = CGPoint(x: mid.x, y: mid.y - (gap + textBlock) / 2)
        textTop = heroCenter.y + hero / 2 + gap

        let margin = 10 * s
        radiusX = max(0, safeW / 2 - tile / 2 - margin)
        radiusY = max(0, safeH / 2 - tile / 2 - margin)
    }

    private static let radiusFactors: [CGFloat] = [1.0, 0.86, 0.96, 0.82, 1.0, 0.9, 0.84, 0.98, 0.88, 0.94]

    /// Resting position of icon `index` in a field of `count` icons: an ellipse
    /// that follows the safe area, so icons enter from the edges at any aspect ratio.
    func fieldPoint(_ index: Int, of count: Int) -> CGPoint {
        guard count > 0 else { return mid }
        let step = 2 * Double.pi / Double(count)
        let angle = -Double.pi / 2 + 0.28 + step * Double(index)
        let factor = Self.radiusFactors[index % Self.radiusFactors.count]
        return CGPoint(
            x: mid.x + radiusX * factor * CGFloat(cos(angle)),
            y: mid.y + radiusY * factor * CGFloat(sin(angle))
        )
    }
}
