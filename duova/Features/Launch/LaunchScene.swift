import SwiftUI

/// A single, still frame of the launch animation at time `t`.
///
/// This view has no timers or state: given the same inputs it always draws
/// the same pixels. `LaunchView` drives it from a `TimelineView`; previews and
/// offline renders can pass any `t`.
struct LaunchScene: View {
    let timeline: LaunchTimeline
    /// Seconds since the sequence began.
    let t: Double
    /// Full container size, including regions under system bars.
    let size: CGSize
    let insets: EdgeInsets

    @Environment(\.duovaTheme) private var theme

    var body: some View {
        let g = LaunchGeometry(size: size, insets: insets)
        let f = timeline.frame(at: t, geometry: g)

        ZStack(alignment: .topLeading) {
            DuovaBackdrop(intensity: f.ambient)

            Canvas { context, _ in
                drawEffects(&context, frame: f, geometry: g)
            }
            .allowsHitTesting(false)

            // The Duova icon sits beneath the travelling icons, so you watch
            // each app fly into it and merge rather than vanish behind it.
            DuovaMark(style: theme.markStyle)
                .frame(width: g.heroSize, height: g.heroSize)
                .scaleEffect(f.heroScale)
                .blur(radius: f.heroBlur)
                .opacity(f.heroOpacity)
                .position(g.heroCenter)

            ForEach(f.icons) { icon in
                ServiceIcon(id: icon.service.id, size: g.tileSize)
                    .drawingGroup()
                    .shadow(color: icon.service.accent.opacity(theme.isDark ? 0.34 : 0.20),
                            radius: g.tileSize * 0.22)
                    .scaleEffect(icon.scale)
                    // Blur grows as the icon melts into the Duova mark.
                    .blur(radius: icon.melt * g.tileSize * 0.16)
                    .opacity(icon.opacity)
                    .position(icon.position)
            }

            if timeline.showsText {
                textBlock(frame: f, geometry: g)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }

    // MARK: Text

    private func textBlock(frame f: LaunchFrame, geometry g: LaunchGeometry) -> some View {
        DuovaLockup(scale: g.scale, wordmarkOpacity: f.wordmarkOpacity, taglineOpacity: f.taglineOpacity)
            .frame(width: min(g.safeWidth * 0.9, 560))
            .frame(width: size.width)
            .padding(.top, g.textTop)
    }

    // MARK: Effects (glow, pulse ring, trails)

    private func drawEffects(_ context: inout GraphicsContext, frame f: LaunchFrame, geometry g: LaunchGeometry) {
        let center = g.heroCenter
        let hero = g.heroSize

        // Radiant glow behind the Duova icon.
        if f.glow > 0 {
            let radius = hero * 1.35
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            let strength = theme.isDark ? 1.0 : 0.7
            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(colors: [
                        theme.glowColors[0].opacity(0.30 * f.glow * strength),
                        theme.glowColors[1].opacity(0.14 * f.glow * strength),
                        .clear
                    ]),
                    center: center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
        }

        // Expanding pulse ring.
        if f.ring > 0 {
            let side = hero * (1 + 0.75 * f.ring)
            let rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
            let path = Path(roundedRect: rect, cornerRadius: DuovaMark.cornerRadius(for: side), style: .continuous)
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [
                        theme.accentColors[0].opacity(0.45 * (1 - f.ring)),
                        theme.accentColors[theme.accentColors.count - 1].opacity(0.45 * (1 - f.ring))
                    ]),
                    startPoint: CGPoint(x: rect.minX, y: rect.minY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
                ),
                lineWidth: max(1, 1.5 * g.scale)
            )
        }

        // Light trails feeding into the icon.
        for icon in f.icons where icon.trailOpacity > 0.01 && icon.trail.count > 1 {
            var path = Path()
            path.move(to: icon.trail[0])
            for point in icon.trail.dropFirst() { path.addLine(to: point) }
            let accent = icon.service.accent
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [
                        accent.opacity(0),
                        accent.opacity(icon.trailOpacity)
                    ]),
                    startPoint: icon.trail[0],
                    endPoint: icon.trail[icon.trail.count - 1]
                ),
                style: StrokeStyle(lineWidth: max(1.5, 2.2 * g.scale), lineCap: .round, lineJoin: .round)
            )
        }
    }
}
