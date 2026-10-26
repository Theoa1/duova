import SwiftUI

enum DuovaMarkStyle {
    case dark
    case light
    /// Monochrome artwork used for the tinted app-icon appearance.
    case mono
}

/// The Duova icon: two adjoining vertical bars on a glass plate with a small
/// "duo" tag at the trailing bottom corner. Everything is proportional to the
/// view's side length, so it renders crisply at any size.
struct DuovaMark: View {
    var style: DuovaMarkStyle = .dark
    /// When true the plate fills the whole square with no border, rounding or
    /// shadow (used to render the 1024pt App Store / home screen artwork, which
    /// iOS masks itself).
    var fullBleed = false
    var showsTag = true

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Plate(style: style, fullBleed: fullBleed, side: s)
                Bars(style: style, side: s)
                if showsTag && s >= 36 {
                    Tag(style: style, side: s)
                }
            }
            .frame(width: s, height: s)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    static func cornerRadius(for side: CGFloat) -> CGFloat { side * 0.26 }
}

private struct Plate: View {
    let style: DuovaMarkStyle
    let fullBleed: Bool
    let side: CGFloat

    private var fill: LinearGradient {
        switch style {
        case .dark:
            LinearGradient(colors: [Color(hex: 0x181A26), Color(hex: 0x090A10)],
                           startPoint: .top, endPoint: .bottom)
        case .light:
            LinearGradient(colors: [Color(hex: 0xFFFFFF), Color(hex: 0xECF0F9)],
                           startPoint: .top, endPoint: .bottom)
        case .mono:
            LinearGradient(colors: [Color(hex: 0x16161A), Color(hex: 0x050506)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private var borderOpacity: Double { style == .dark ? 0.70 : 0.40 }

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: fullBleed ? 0 : DuovaMark.cornerRadius(for: side),
            style: .continuous
        )
        ZStack {
            shape.fill(fill)
            if style == .dark || style == .mono {
                // Soft inner light from the top-leading corner.
                shape.fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.07), .clear],
                        center: UnitPoint(x: 0.2, y: 0.1),
                        startRadius: 0,
                        endRadius: side * 0.8
                    )
                )
            }
            if !fullBleed && style != .mono {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [DuovaPalette.blue.opacity(borderOpacity),
                                 DuovaPalette.purple.opacity(borderOpacity)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(1, side * 0.016)
                )
            }
        }
        .shadow(
            color: fullBleed ? .clear
                : (style == .dark ? DuovaPalette.blue.opacity(0.30) : Color.black.opacity(0.10)),
            radius: side * 0.12,
            y: style == .dark ? 0 : side * 0.04
        )
    }
}

private struct Bars: View {
    let style: DuovaMarkStyle
    let side: CGFloat

    private var leftColors: [Color] {
        style == .mono ? [Color.white.opacity(0.96), Color.white.opacity(0.72)]
                       : [DuovaPalette.teal, DuovaPalette.blue]
    }

    private var rightColors: [Color] {
        style == .mono ? [Color.white.opacity(0.78), Color.white.opacity(0.50)]
                       : [DuovaPalette.indigo, DuovaPalette.purple]
    }

    var body: some View {
        let width = side * 0.175
        let height = side * 0.46
        let gap = side * 0.05
        let radius = side * 0.075
        HStack(spacing: gap) {
            bar(width: width, height: height, radius: radius, colors: leftColors)
            bar(width: width, height: height, radius: radius, colors: rightColors)
        }
        .frame(width: side, height: side)
        .offset(y: -side * 0.055)
    }

    private func bar(width: CGFloat, height: CGFloat, radius: CGFloat, colors: [Color]) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return shape
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .overlay(
                shape.fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.26), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
            )
            .frame(width: width, height: height)
            .shadow(
                color: style == .dark ? colors[colors.count - 1].opacity(0.35) : .clear,
                radius: side * 0.05
            )
    }
}

private struct Tag: View {
    let style: DuovaMarkStyle
    let side: CGFloat

    private var color: Color {
        switch style {
        case .dark: Color.white.opacity(0.82)
        case .light: Color(hex: 0x0F172A, opacity: 0.62)
        case .mono: Color.white.opacity(0.7)
        }
    }

    var body: some View {
        Text(verbatim: "duo")
            .font(.system(size: side * 0.125, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .fixedSize()
            .frame(width: side, height: side, alignment: .bottomTrailing)
            .offset(x: -side * 0.10, y: -side * 0.075)
    }
}
