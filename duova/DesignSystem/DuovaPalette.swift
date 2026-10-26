import SwiftUI

extension Color {
    /// Creates an sRGB color from a 24-bit `0xRRGGBB` literal.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Duova brand colors.
///
/// The hues follow the original brand set (`#0A84FF`, `#5E5CE6`, `#BF5AF2`,
/// `#FF375F`, `#64D2FF`, `#30D158`, `#FF9F0A`) but are deliberately softened:
/// lower saturation and slightly lower brightness so glows and gradients read
/// as premium and calm rather than neon.
enum DuovaPalette {
    static let blue = Color(hex: 0x4F86D9)
    static let indigo = Color(hex: 0x6A69C9)
    static let purple = Color(hex: 0x9B6FC9)
    static let pink = Color(hex: 0xC76683)
    static let teal = Color(hex: 0x6DB3D1)
    static let emerald = Color(hex: 0x58A97C)
    static let amber = Color(hex: 0xCE9A55)

    /// Signature gradient: blue → indigo → purple.
    static let brandColors: [Color] = [blue, indigo, purple]
}
