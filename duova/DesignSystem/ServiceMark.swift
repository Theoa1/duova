import SwiftUI

/// Vector renditions of the services' app icons, drawn in code so they stay
/// sharp at any size without bundled bitmaps.
///
/// Every mark uses the same modern construction: a soft top-to-bottom
/// gradient base, a clean glyph with rounded joins, and a gentle drop shadow
/// that lifts the glyph off the base.
///
/// These are identification marks for third-party services. Names and logos
/// belong to their respective owners; Duova is independent and not affiliated
/// with them. Before public release, provenance and permission for each mark
/// must be reviewed (blueprint §26, §29).
struct ServiceMark: View {
    let id: ServiceID

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            context.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
            var art = MarkArtist(context: context, s: side)
            art.draw(id)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// A service icon in the iOS continuous-corner icon shape with a glass finish:
/// full-strength artwork, a soft specular sheen across the top, a bright rim
/// light that fades around the edge, and a faint inner glow along the bottom.
struct ServiceIcon: View {
    @Environment(\.duovaTheme) private var theme
    let id: ServiceID
    var size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
        let rim = max(0.75, size * 0.018)

        ServiceMark(id: id)
            .frame(width: size, height: size)
            .overlay {
                // Specular sheen: bright at the top, gone by the middle.
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.30), location: 0),
                            .init(color: Color.white.opacity(0.06), location: 0.36),
                            .init(color: Color.white.opacity(0), location: 0.52)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.plusLighter)
            }
            .overlay {
                // Soft glow gathering at the lower edge, as light does inside glass.
                shape.fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.14), .clear],
                        center: UnitPoint(x: 0.5, y: 1.05),
                        startRadius: 0,
                        endRadius: size * 0.7
                    )
                )
                .blendMode(.plusLighter)
            }
            .clipShape(shape)
            .overlay {
                // Rim light: strongest at the top-leading edge, faint opposite.
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.80),
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.30)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: rim
                )
            }
            .overlay {
                // Thin dark keyline keeps pale icons defined on light backgrounds.
                shape.inset(by: -rim * 0.5)
                    .strokeBorder(Color.black.opacity(theme.isDark ? 0.35 : 0.12), lineWidth: rim * 0.6)
            }
            .shadow(color: Color.black.opacity(theme.isDark ? 0.45 : 0.18), radius: size * 0.10, y: size * 0.05)
    }
}

// MARK: - Artwork

/// Draws one mark in a unit square scaled to `s` points. Coordinates below are
/// fractions of the icon's side.
private struct MarkArtist {
    var context: GraphicsContext
    let s: CGFloat

    mutating func draw(_ id: ServiceID) {
        switch id {
        case .instagram: instagram()
        case .youtube: youtube()
        case .spotify: spotify()
        case .googleMaps: maps()
        case .tiktok: tiktok()
        case .gmail: gmail()
        case .excel: excel()
        case .twitch: twitch()
        case .googleDocs: googlePage(body: [0x5B9BFF, 0x2F6FE0], fold: 0xB7D2FF, slide: false)
        case .googleSlides: googlePage(body: [0xFFCB3D, 0xF2A600], fold: 0xFFE7A0, slide: true)
        }
    }

    // MARK: Helpers

    private func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
    private func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
    }
    private var full: Path { Path(r(0, 0, 1, 1)) }

    private func vertical(_ top: UInt32, _ bottom: UInt32) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: [Color(hex: top), Color(hex: bottom)]), startPoint: p(0.5, 0), endPoint: p(0.5, 1))
    }

    private func base(_ top: UInt32, _ bottom: UInt32) {
        context.fill(full, with: vertical(top, bottom))
    }

    /// Draws the glyph on its own layer with a soft shadow beneath it.
    private func glyph(shadow: Double = 0.22, _ draw: (inout GraphicsContext) -> Void) {
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(shadow), radius: s * 0.03, x: 0, y: s * 0.016))
            draw(&layer)
        }
    }

    /// A polygon whose corners are rounded with radius `radius` (in unit space).
    private func rounded(_ points: [CGPoint], radius: CGFloat) -> Path {
        var path = Path()
        guard let last = points.last, let first = points.first else { return path }
        path.move(to: CGPoint(x: (last.x + first.x) / 2 * s, y: (last.y + first.y) / 2 * s))
        for index in points.indices {
            let corner = points[index]
            let next = points[(index + 1) % points.count]
            path.addArc(tangent1End: p(corner.x, corner.y), tangent2End: p(next.x, next.y), radius: radius * s)
        }
        path.closeSubpath()
        return path
    }

    private func circle(_ cx: CGFloat, _ cy: CGFloat, _ radius: CGFloat) -> Path {
        Path(ellipseIn: r(cx - radius, cy - radius, radius * 2, radius * 2))
    }

    private func roundedRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ corner: CGFloat) -> Path {
        Path(roundedRect: r(x, y, w, h), cornerRadius: corner * s, style: .continuous)
    }

    private func line(_ points: [(CGFloat, CGFloat)]) -> Path {
        var path = Path()
        path.addLines(points.map { p($0.0, $0.1) })
        return path
    }

    private func roundStroke(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width * s, lineCap: .round, lineJoin: .round)
    }

    // MARK: Marks

    private func instagram() {
        context.fill(full, with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(hex: 0xFEDA75), location: 0),
                .init(color: Color(hex: 0xFA7E1E), location: 0.26),
                .init(color: Color(hex: 0xD62976), location: 0.55),
                .init(color: Color(hex: 0x962FBF), location: 0.8),
                .init(color: Color(hex: 0x4F5BD5), location: 1),
            ]),
            startPoint: p(0.1, 1), endPoint: p(0.9, 0)))
        context.fill(full, with: .radialGradient(
            Gradient(colors: [Color(hex: 0xFFD45E, opacity: 0.85), .clear]),
            center: p(0.2, 1.04), startRadius: 0, endRadius: s * 0.6))
        glyph(shadow: 0.18) { layer in
            let white = GraphicsContext.Shading.color(.white)
            layer.stroke(roundedRect(0.215, 0.215, 0.57, 0.57, 0.17), with: white, lineWidth: 0.074 * s)
            layer.stroke(circle(0.5, 0.5, 0.135), with: white, lineWidth: 0.074 * s)
            layer.fill(circle(0.665, 0.335, 0.042), with: white)
        }
    }

    private func youtube() {
        base(0xFF5A4E, 0xD9001A)
        context.fill(full, with: .radialGradient(
            Gradient(colors: [Color.white.opacity(0.18), .clear]),
            center: p(0.5, 0), startRadius: 0, endRadius: s * 0.7))
        glyph { layer in
            layer.fill(rounded([p1(0.39, 0.285), p1(0.745, 0.5), p1(0.39, 0.715)], radius: 0.07), with: .color(.white))
        }
    }

    private func spotify() {
        base(0x232326, 0x060606)
        glyph(shadow: 0.35) { layer in
            layer.fill(circle(0.5, 0.5, 0.36), with: .linearGradient(
                Gradient(colors: [Color(hex: 0x45EA82), Color(hex: 0x19B04D)]),
                startPoint: p(0.5, 0.14), endPoint: p(0.5, 0.86)))
        }
        let ink = GraphicsContext.Shading.color(Color(hex: 0x111214))
        for (y, half, depth, width) in [(0.415, 0.215, 0.075, 0.066), (0.525, 0.175, 0.058, 0.057), (0.625, 0.13, 0.042, 0.048)] {
            var wave = Path()
            wave.move(to: p(0.5 - half, y))
            wave.addQuadCurve(to: p(0.5 + half, y + depth * 0.45), control: p(0.5, y - depth))
            context.stroke(wave, with: ink, style: roundStroke(width))
        }
    }

    private func maps() {
        base(0xFFFFFF, 0xE9EEF3)
        // Pin: a circle that narrows to a rounded point.
        var pin = Path()
        pin.addArc(center: p(0.5, 0.4), radius: 0.235 * s, startAngle: .degrees(150), endAngle: .degrees(30), clockwise: false)
        pin.addQuadCurve(to: p(0.5, 0.86), control: p(0.6, 0.66))
        pin.addQuadCurve(to: p(0.5 - 0.235 * cos(.pi / 6), 0.4 + 0.235 * sin(.pi / 6)), control: p(0.4, 0.66))
        pin.closeSubpath()
        let center: (CGFloat, CGFloat) = (0.5, 0.4)
        glyph(shadow: 0.2) { layer in
            layer.drawLayer { inner in
                inner.clip(to: pin)
                inner.fill(full, with: .color(Color(hex: 0x34A853)))
                inner.fill(line([center, (0.5, 0), (1, 0), (1, 0.3)]), with: .color(Color(hex: 0xEA4335)))
                inner.fill(line([center, (0.5, 0), (0, 0), (0, 0.3)]), with: .color(Color(hex: 0x4285F4)))
                inner.fill(line([center, (0, 0.3), (0, 0.66)]), with: .color(Color(hex: 0xFBBC04)))
            }
        }
        context.fill(circle(0.5, 0.4, 0.088), with: .color(.white))
    }

    private func tiktok() {
        base(0x1C1C21, 0x000000)
        var note = Path()
        note.move(to: p(0.575, 0.66))
        note.addLine(to: p(0.575, 0.2))
        note.addCurve(to: p(0.75, 0.35), control1: p(0.58, 0.29), control2: p(0.65, 0.35))
        note.move(to: p(0.5355, 0.5045))
        note.addArc(center: p(0.44, 0.6), radius: 0.135 * s, startAngle: .degrees(-45), endAngle: .degrees(315), clockwise: false)
        let style = roundStroke(0.095)
        context.stroke(note.offsetBy(dx: -0.02 * s, dy: -0.014 * s), with: .color(Color(hex: 0x25F4EE)), style: style)
        context.stroke(note.offsetBy(dx: 0.02 * s, dy: 0.014 * s), with: .color(Color(hex: 0xFE2C55)), style: style)
        glyph(shadow: 0.25) { layer in
            layer.stroke(note, with: .color(.white), style: style)
        }
    }

    private func gmail() {
        base(0xFFFFFF, 0xEDF0F4)
        let stroke = StrokeStyle(lineWidth: 0.125 * s, lineCap: .round, lineJoin: .round)
        glyph(shadow: 0.14) { layer in
            layer.stroke(line([(0.235, 0.705), (0.235, 0.37)]), with: .color(Color(hex: 0x4285F4)), style: stroke)
            layer.stroke(line([(0.765, 0.705), (0.765, 0.37)]), with: .color(Color(hex: 0x34A853)), style: stroke)
            layer.stroke(line([(0.235, 0.37), (0.5, 0.565), (0.765, 0.37)]), with: .color(Color(hex: 0xEA4335)), style: stroke)
            layer.stroke(line([(0.235, 0.37), (0.31, 0.425)]), with: .color(Color(hex: 0xC5221F)), style: stroke)
            layer.stroke(line([(0.69, 0.425), (0.765, 0.37)]), with: .color(Color(hex: 0xFBBC04)), style: stroke)
        }
    }

    private func excel() {
        base(0xEFFAF3, 0xD3EEDD)
        // The sheet: three green bands with column rules.
        let sheet = roundedRect(0.3, 0.18, 0.52, 0.64, 0.07)
        glyph(shadow: 0.14) { layer in
            layer.drawLayer { inner in
                inner.clip(to: sheet)
                inner.fill(Path(r(0.3, 0.18, 0.52, 0.22)), with: .color(Color(hex: 0x33C481)))
                inner.fill(Path(r(0.3, 0.40, 0.52, 0.21)), with: .color(Color(hex: 0x21A366)))
                inner.fill(Path(r(0.3, 0.61, 0.52, 0.21)), with: .color(Color(hex: 0x107C41)))
                inner.stroke(line([(0.64, 0.18), (0.64, 0.82)]), with: .color(.white.opacity(0.35)), lineWidth: 0.012 * s)
            }
        }
        // The "X" tile in front.
        glyph(shadow: 0.28) { layer in
            layer.fill(roundedRect(0.15, 0.31, 0.38, 0.38, 0.075), with: .linearGradient(
                Gradient(colors: [Color(hex: 0x1D8F4E), Color(hex: 0x0B5E30)]),
                startPoint: p(0.34, 0.31), endPoint: p(0.34, 0.69)))
            let x = roundStroke(0.06)
            layer.stroke(line([(0.255, 0.415), (0.425, 0.585)]), with: .color(.white), style: x)
            layer.stroke(line([(0.425, 0.415), (0.255, 0.585)]), with: .color(.white), style: x)
        }
    }

    private func twitch() {
        base(0xA673FF, 0x7426F2)
        glyph(shadow: 0.25) { layer in
            let bubble = rounded([
                p1(0.26, 0.2), p1(0.76, 0.2), p1(0.76, 0.55), p1(0.6, 0.71),
                p1(0.49, 0.71), p1(0.39, 0.81), p1(0.39, 0.71), p1(0.26, 0.71),
            ], radius: 0.025)
            layer.fill(bubble, with: .color(.white))
            let eye = GraphicsContext.Shading.color(Color(hex: 0x8C45FF))
            layer.fill(roundedRect(0.445, 0.34, 0.062, 0.17, 0.02), with: eye)
            layer.fill(roundedRect(0.59, 0.34, 0.062, 0.17, 0.02), with: eye)
        }
    }

    /// Google Docs and Slides: a page with a folded corner.
    private func googlePage(body: [UInt32], fold: UInt32, slide: Bool) {
        base(0xFFFFFF, slide ? 0xFFF4DA : 0xEAF0FA)
        let x: CGFloat = 0.25, y: CGFloat = 0.14, w: CGFloat = 0.5, h: CGFloat = 0.72
        let cut = w * 0.34
        let page = rounded([p1(x, y), p1(x + w - cut, y), p1(x + w, y + cut), p1(x + w, y + h), p1(x, y + h)], radius: 0.035)
        glyph(shadow: 0.16) { layer in
            layer.fill(page, with: .linearGradient(
                Gradient(colors: body.map { Color(hex: $0) }),
                startPoint: p(0.5, y), endPoint: p(0.5, y + h)))
            layer.fill(rounded([p1(x + w - cut, y), p1(x + w, y + cut), p1(x + w - cut, y + cut)], radius: 0.012),
                       with: .color(Color(hex: fold)))
            if slide {
                layer.stroke(roundedRect(0.335, 0.475, 0.33, 0.22, 0.025), with: .color(.white), lineWidth: 0.045 * s)
            } else {
                for (index, top) in [0.44, 0.52, 0.6, 0.68].enumerated() {
                    let width: CGFloat = index == 3 ? 0.2 : 0.32
                    layer.fill(roundedRect(0.34, top, width, 0.04, 0.02), with: .color(.white))
                }
            }
        }
    }

    /// A unit-space point, for `rounded(_:radius:)`.
    private func p1(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
}
