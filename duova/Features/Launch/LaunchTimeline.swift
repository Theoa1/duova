import SwiftUI

/// State of one floating service icon at a point in time.
struct LaunchIcon: Identifiable {
    let service: Service
    var id: ServiceID { service.id }
    var position: CGPoint
    var scale: CGFloat
    var opacity: Double
    /// Recent positions, oldest first, ending at `position`. Drives the light trail.
    var trail: [CGPoint]
    var trailOpacity: Double
}

/// Everything the scene draws at one instant.
struct LaunchFrame {
    var ambient: Double
    var heroOpacity: Double
    var heroScale: CGFloat
    /// Blur radius in points.
    var heroBlur: CGFloat
    var glow: Double
    /// 0 when inactive, otherwise 0...1 progress of the expanding pulse ring.
    var ring: Double
    var wordmarkOpacity: Double
    var taglineOpacity: Double
    var icons: [LaunchIcon]
}

/// Pure, deterministic description of the launch animation.
///
/// Phases (per blueprint §17 and the design brief):
/// 1. **Appear**: the glow fades in and icons float in from the edges.
/// 2. **Converge**: icons drift inward on curved paths; the Duova icon sharpens.
/// 3. **Morph**: icons dissolve into light trails; the icon pulses.
/// 4. **Reveal**: the wordmark and tagline fade in, then the screen hands off.
///
/// Because the frame is a function of elapsed time only, it renders identically
/// in a `TimelineView`, in SwiftUI previews, and in offline renders.
struct LaunchTimeline {
    let variant: LaunchVariant
    let reducesMotion: Bool

    let appear: ClosedRange<Double>
    let converge: ClosedRange<Double>
    let morph: ClosedRange<Double>
    let reveal: ClosedRange<Double>
    /// Seconds until the launch overlay should hand off to the app.
    let total: Double
    let iconCount: Int
    let showsText: Bool

    init(variant: LaunchVariant, reducesMotion: Bool = false) {
        self.variant = variant
        self.reducesMotion = reducesMotion
        showsText = variant != .resume

        if reducesMotion {
            // Calm crossfade: no travelling icons, no pulse.
            appear = 0...0.2
            converge = 0...0.25
            morph = 0.25...0.25
            reveal = 0.12...0.38
            total = variant == .resume ? 0.3 : 0.55
            iconCount = 0
            return
        }

        switch variant {
        case .full:
            appear = 0...0.40
            converge = 0.36...1.02
            morph = 1.02...1.30
            reveal = 1.12...1.46
            total = 1.70
            iconCount = 10
        case .quick:
            appear = 0...0.14
            converge = 0.14...0.50
            morph = 0.50...0.68
            reveal = 0.56...0.74
            total = 0.85
            iconCount = 6
        case .resume:
            appear = 0...0.10
            converge = 0...0.14
            morph = 0.10...0.32
            reveal = 0.10...0.10
            total = 0.35
            iconCount = 0
        }
    }

    // MARK: Frame

    func frame(at rawTime: Double, geometry g: LaunchGeometry) -> LaunchFrame {
        let t = Motion.clamp(rawTime, 0, total)
        let services = ServiceCatalog.launchServices(count: iconCount)

        let activation = Motion.easeInOut(Motion.progress(t, in: converge))
        let morphProgress = Motion.progress(t, in: morph)
        let pulse = reducesMotion ? 0 : sin(Double.pi * morphProgress)
        let ambient = Motion.easeOut(Motion.progress(t, in: 0...max(appear.upperBound, 0.2)))

        let taglineRange = (reveal.lowerBound + 0.06)...(reveal.upperBound + 0.06)

        var icons: [LaunchIcon] = []
        icons.reserveCapacity(services.count)
        for (index, service) in services.enumerated() {
            let now = placement(index, at: t, in: g)
            // A short history of the same path forms the trailing light streak.
            let step = (converge.upperBound - converge.lowerBound) * 0.045
            var trail: [CGPoint] = []
            for k in stride(from: 5, through: 1, by: -1) {
                trail.append(placement(index, at: max(0, t - Double(k) * step), in: g).position)
            }
            trail.append(now.position)
            icons.append(LaunchIcon(
                service: service,
                position: now.position,
                scale: now.scale,
                opacity: now.opacity,
                trail: trail,
                trailOpacity: now.trailOpacity
            ))
        }

        return LaunchFrame(
            ambient: ambient,
            heroOpacity: 0.34 + 0.66 * activation,
            heroScale: CGFloat((0.9 + 0.1 * activation) * (1 + 0.06 * pulse)),
            heroBlur: CGFloat(1 - activation) * 7 * g.scale,
            glow: min(1, 0.3 * activation + 0.7 * pulse),
            ring: (!reducesMotion && morphProgress > 0 && morphProgress < 1) ? morphProgress : 0,
            wordmarkOpacity: showsText ? Motion.easeOut(Motion.progress(t, in: reveal)) : 0,
            taglineOpacity: showsText ? Motion.easeOut(Motion.progress(t, in: taglineRange)) : 0,
            icons: icons
        )
    }

    // MARK: Icon motion

    private struct Placement {
        var position: CGPoint
        var scale: CGFloat
        var opacity: Double
        var trailOpacity: Double
    }

    private func placement(_ index: Int, at t: Double, in g: LaunchGeometry) -> Placement {
        let n = max(iconCount, 1)
        let field = g.fieldPoint(index, of: iconCount)
        let target = g.heroCenter

        // Icons start pushed outward and settle onto the field ("float in from the edges").
        let origin = CGPoint(
            x: g.mid.x + (field.x - g.mid.x) * 1.28,
            y: g.mid.y + (field.y - g.mid.y) * 1.28
        )
        let appearSpan = appear.upperBound - appear.lowerBound
        let appearStart = appear.lowerBound + Double(index) * appearSpan * 0.45 / Double(n)
        let a = Motion.easeOut(Motion.progress(t, in: appearStart...appear.upperBound))

        let convergeSpan = converge.upperBound - converge.lowerBound
        let convergeStart = converge.lowerBound + Double(index) * convergeSpan * 0.25 / Double(n)
        let c = Motion.easeInOut(Motion.progress(t, in: convergeStart...converge.upperBound))

        let m = Motion.progress(t, in: morph)

        // Gentle floating drift while waiting on the field.
        let amplitude = g.tileSize * 0.12
        let omega = 1.3 + 0.17 * Double(index)
        let phase = 1.7 * Double(index)
        let driftWeight = (1 - c) * a
        let drift = CGPoint(
            x: CGFloat(sin(t * omega + phase) * driftWeight) * amplitude,
            y: CGFloat(cos(t * omega * 0.83 + phase) * driftWeight) * amplitude
        )

        let base = Motion.lerp(origin, field, a)
        let linear = Motion.lerp(CGPoint(x: base.x + drift.x, y: base.y + drift.y), target, c)

        // A perpendicular bow makes each path a soft arc instead of a straight line.
        let dx = field.x - target.x
        let dy = field.y - target.y
        let length = max(1, hypot(dx, dy))
        let bow = CGFloat(sin(Double.pi * c)) * length * 0.14 * (index.isMultiple(of: 2) ? 1 : -1)
        let position = CGPoint(
            x: linear.x + (-dy / length) * bow,
            y: linear.y + (dx / length) * bow
        )

        let scale = CGFloat((0.55 + 0.45 * a) * Motion.lerp(1, 0.55, c) * Motion.lerp(1, 0.2, Motion.easeIn(m)))
        let opacity = a * (1 - Motion.easeIn(m)) * (1 - 0.25 * c)
        let trailOpacity = sin(Double.pi * c) * 0.55 * (1 - m)

        return Placement(position: position, scale: scale, opacity: opacity, trailOpacity: trailOpacity)
    }
}
