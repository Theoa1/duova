import CoreGraphics
import Foundation

/// Small, allocation-free helpers shared by the launch timeline.
enum Motion {
    static func clamp(_ value: Double, _ lower: Double = 0, _ upper: Double = 1) -> Double {
        min(max(value, lower), upper)
    }

    static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }

    /// Normalized progress (0...1) of `t` through `range`.
    /// A zero-length range behaves like a step.
    static func progress(_ t: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return t >= range.lowerBound ? 1 : 0 }
        return clamp((t - range.lowerBound) / span)
    }

    /// Smoothstep: gentle at both ends without the abrupt middle of a cubic.
    static func easeInOut(_ x: Double) -> Double {
        x * x * (3 - 2 * x)
    }

    static func easeOut(_ x: Double) -> Double {
        1 - pow(1 - x, 3)
    }

    static func easeIn(_ x: Double) -> Double {
        x * x * x
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t))
    }
}
