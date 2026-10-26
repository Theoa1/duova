import SwiftUI

/// Vector renditions of the services' app icons, drawn in SwiftUI so they
/// scale to any size without bundled bitmaps.
///
/// These are identification marks for third-party services. Names and logos
/// belong to their respective owners; Duova is independent and not affiliated
/// with them. Before public release, provenance and permission for each mark
/// must be reviewed (blueprint §26, §29).
struct ServiceMark: View {
    let id: ServiceID

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            artwork(side: s)
                .frame(width: s, height: s)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func artwork(side s: CGFloat) -> some View {
        switch id {
        case .instagram: InstagramArt(s: s)
        case .youtube: YouTubeArt(s: s)
        case .spotify: SpotifyArt(s: s)
        case .googleMaps: MapsArt(s: s)
        case .tiktok: TikTokArt(s: s)
        case .gmail: GmailArt(s: s)
        case .whatsapp: WhatsAppArt(s: s)
        case .netflix: NetflixArt(s: s)
        case .googleDocs: DocsArt(s: s)
        case .uber: UberArt(s: s)
        }
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
            // Punchy, full-strength color under the glass.
            .saturation(1.1)
            .contrast(1.05)
            .overlay {
                // Specular sheen: bright at the top, gone by the middle.
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.42), location: 0),
                            .init(color: Color.white.opacity(0.10), location: 0.38),
                            .init(color: Color.white.opacity(0), location: 0.55)
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
                        colors: [Color.white.opacity(0.20), .clear],
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
                            Color.white.opacity(0.85),
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.35)
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

private struct InstagramArt: View {
    let s: CGFloat
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0xFFD65C), location: 0.0),
                    .init(color: Color(hex: 0xFF9A2E), location: 0.22),
                    .init(color: Color(hex: 0xE8306F), location: 0.52),
                    .init(color: Color(hex: 0x8A3AB9), location: 0.78),
                    .init(color: Color(hex: 0x4A5FE8), location: 1.0)
                ],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
            RoundedRectangle(cornerRadius: s * 0.16, style: .continuous)
                .strokeBorder(Color.white, lineWidth: s * 0.07)
                .frame(width: s * 0.52, height: s * 0.52)
            Circle()
                .strokeBorder(Color.white, lineWidth: s * 0.07)
                .frame(width: s * 0.25, height: s * 0.25)
            Circle()
                .fill(Color.white)
                .frame(width: s * 0.07, height: s * 0.07)
                .offset(x: s * 0.15, y: -s * 0.15)
        }
    }
}

private struct YouTubeArt: View {
    let s: CGFloat
    var body: some View {
        ZStack {
            Color(hex: 0xFAFAFA)
            RoundedRectangle(cornerRadius: s * 0.14, style: .continuous)
                .fill(Color(hex: 0xFF2B2B))
                .frame(width: s * 0.70, height: s * 0.49)
            Triangle()
                .fill(Color.white)
                .frame(width: s * 0.17, height: s * 0.19)
                .offset(x: s * 0.012)
        }
    }
}

private struct SpotifyArt: View {
    let s: CGFloat
    var body: some View {
        ZStack {
            Color(hex: 0x1ED760)
            Circle()
                .fill(Color(hex: 0x0C0F0D))
                .frame(width: s * 0.66, height: s * 0.66)
            wave(width: s * 0.40, thickness: s * 0.055, curve: s * 0.07, y: -s * 0.115)
            wave(width: s * 0.32, thickness: s * 0.048, curve: s * 0.055, y: -s * 0.015)
            wave(width: s * 0.23, thickness: s * 0.042, curve: s * 0.04, y: s * 0.075)
        }
    }

    private func wave(width: CGFloat, thickness: CGFloat, curve: CGFloat, y: CGFloat) -> some View {
        Arc(curve: curve)
            .stroke(Color(hex: 0x1ED760), style: StrokeStyle(lineWidth: thickness, lineCap: .round))
            .frame(width: width, height: curve)
            .offset(y: y)
    }
}

private struct MapsArt: View {
    let s: CGFloat
    var body: some View {
        ZStack {
            Color(hex: 0xF2F5EC)
            // Park, water, and road shapes.
            Rectangle()
                .fill(Color(hex: 0x86D17E))
                .frame(width: s * 0.5, height: s * 0.42)
                .position(x: s * 0.25, y: s * 0.21)
            Rectangle()
                .fill(Color(hex: 0x6FB2F7))
                .frame(width: s * 0.38, height: s * 0.5)
                .position(x: s * 0.81, y: s * 0.75)
            Rectangle()
                .fill(Color.white)
                .frame(width: s * 0.09, height: s * 1.5)
                .rotationEffect(.degrees(-38))
            Rectangle()
                .fill(Color(hex: 0xFFD04D))
                .frame(width: s * 1.5, height: s * 0.06)
                .rotationEffect(.degrees(18))
                .offset(y: s * 0.18)
            // Pin.
            Pin()
                .fill(Color(hex: 0xF03E32))
                .frame(width: s * 0.30, height: s * 0.44)
                .shadow(color: Color.black.opacity(0.18), radius: s * 0.02, y: s * 0.01)
                .offset(y: -s * 0.04)
            Circle()
                .fill(Color.white)
                .frame(width: s * 0.11, height: s * 0.11)
                .offset(y: -s * 0.115)
        }
    }
}

private struct TikTokArt: View {
    let s: CGFloat
    var body: some View {
        ZStack {
            Color(hex: 0x0B0B0D)
            note(Color(hex: 0x25F4EE)).offset(x: -s * 0.018, y: -s * 0.012)
            note(Color(hex: 0xFE2C55)).offset(x: s * 0.018, y: s * 0.012)
            note(Color.white)
        }
    }

    private func note(_ color: Color) -> some View {
        TikTokNote()
            .stroke(color, style: StrokeStyle(lineWidth: s * 0.095, lineCap: .round, lineJoin: .round))
            .frame(width: s, height: s)
    }
}

private struct GmailArt: View {
    let s: CGFloat
    var body: some View {
        ZStack {
            Color(hex: 0xFAFAFA)
            GmailM()
                .stroke(Color(hex: 0xEA4335), style: StrokeStyle(lineWidth: s * 0.115, lineCap: .butt, lineJoin: .miter))
                .frame(width: s, height: s)
            // Darker outer edges give the envelope its folded look.
            Rectangle()
                .fill(Color(hex: 0xB8271E))
                .frame(width: s * 0.115, height: s * 0.40)
                .position(x: s * 0.2, y: s * 0.52)
            Rectangle()
                .fill(Color(hex: 0xB8271E))
                .frame(width: s * 0.115, height: s * 0.40)
                .position(x: s * 0.8, y: s * 0.52)
        }
    }
}

private struct WhatsAppArt: View {
    let s: CGFloat
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x62F27F), Color(hex: 0x1FCC5E)],
                           startPoint: .top, endPoint: .bottom)
            Bubble()
                .stroke(Color.white, style: StrokeStyle(lineWidth: s * 0.062, lineJoin: .round))
                .frame(width: s * 0.60, height: s * 0.60)
                .offset(y: -s * 0.005)
            Image(systemName: "phone.fill")
                .font(.system(size: s * 0.27, weight: .bold))
                .foregroundStyle(Color.white)
                .scaleEffect(x: -1, y: 1)
                .offset(x: -s * 0.002, y: -s * 0.012)
        }
    }
}

private struct NetflixArt: View {
    let s: CGFloat
    var body: some View {
        let frame = CGSize(width: s * 0.36, height: s * 0.58)
        ZStack {
            Color(hex: 0x0A0A0A)
            NetflixStroke(kind: .bar(leading: true))
                .fill(Color(hex: 0xB20710))
                .frame(width: frame.width, height: frame.height)
            NetflixStroke(kind: .bar(leading: false))
                .fill(Color(hex: 0xB20710))
                .frame(width: frame.width, height: frame.height)
            NetflixStroke(kind: .diagonal)
                .fill(Color(hex: 0xF0111C))
                .frame(width: frame.width, height: frame.height)
        }
    }
}

private struct DocsArt: View {
    let s: CGFloat
    var body: some View {
        ZStack {
            Color(hex: 0xF3F6FC)
            DocPage()
                .fill(Color(hex: 0x3B82F6))
                .frame(width: s * 0.5, height: s * 0.66)
            DocFold()
                .fill(Color(hex: 0x9CC0FF))
                .frame(width: s * 0.5, height: s * 0.66)
            VStack(spacing: s * 0.05) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule().fill(Color.white).frame(width: s * 0.28, height: s * 0.035)
                }
            }
            .offset(y: s * 0.1)
        }
    }
}

private struct UberArt: View {
    let s: CGFloat
    var body: some View {
        ZStack {
            Color(hex: 0x0B0B0B)
            Text(verbatim: "Uber")
                .font(.system(size: s * 0.27, weight: .semibold))
                .tracking(-s * 0.006)
                .foregroundStyle(Color.white)
                .fixedSize()
        }
    }
}

// MARK: - Shapes

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// An upward-bulging arc spanning the shape's width.
private struct Arc: Shape {
    let curve: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                       control: CGPoint(x: rect.midX, y: rect.maxY - curve * 2))
        return p
    }
}

/// Map pin: a circle on a point.
private struct Pin: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.minY + r)
        p.addArc(center: center, radius: r, startAngle: .degrees(150), endAngle: .degrees(30), clockwise: false)
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Stroked outline of a music note with a flag.
private struct TikTokNote: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var p = Path()
        // Stem and flag.
        p.move(to: pt(0.575, 0.66))
        p.addLine(to: pt(0.575, 0.2))
        p.addCurve(to: pt(0.75, 0.35), control1: pt(0.58, 0.29), control2: pt(0.65, 0.35))
        // Note head.
        p.move(to: pt(0.5355, 0.5045))
        p.addArc(center: pt(0.44, 0.60), radius: 0.135 * w, startAngle: .degrees(-45), endAngle: .degrees(315), clockwise: false)
        return p
    }
}

private struct GmailM: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 0.2 * w, y: rect.minY + 0.72 * h))
        p.addLine(to: CGPoint(x: rect.minX + 0.2 * w, y: rect.minY + 0.30 * h))
        p.addLine(to: CGPoint(x: rect.minX + 0.5 * w, y: rect.minY + 0.56 * h))
        p.addLine(to: CGPoint(x: rect.minX + 0.8 * w, y: rect.minY + 0.30 * h))
        p.addLine(to: CGPoint(x: rect.minX + 0.8 * w, y: rect.minY + 0.72 * h))
        return p
    }
}

private struct Bubble: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = rect.width / 2
        // Circle with a tail at the lower leading corner.
        p.addArc(center: c, radius: r, startAngle: .degrees(150), endAngle: .degrees(125), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX - rect.width * 0.02, y: rect.maxY + rect.height * 0.08))
        p.closeSubpath()
        return p
    }
}

private struct NetflixStroke: Shape {
    enum Kind {
        case bar(leading: Bool)
        case diagonal
    }

    let kind: Kind

    func path(in rect: CGRect) -> Path {
        let bar = rect.width * 0.27
        var p = Path()
        switch kind {
        case .bar(let leading):
            let x = leading ? rect.minX : rect.maxX - bar
            p.move(to: CGPoint(x: x, y: rect.minY))
            p.addLine(to: CGPoint(x: x + bar, y: rect.minY))
            p.addLine(to: CGPoint(x: x + bar, y: rect.maxY))
            p.addLine(to: CGPoint(x: x, y: rect.maxY))
        case .diagonal:
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX + bar, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX - bar, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}

private struct DocPage: Shape {
    func path(in rect: CGRect) -> Path {
        let fold = rect.width * 0.34
        let r = rect.width * 0.08
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

private struct DocFold: Shape {
    func path(in rect: CGRect) -> Path {
        let fold = rect.width * 0.34
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        p.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY + fold))
        p.closeSubpath()
        return p
    }
}
