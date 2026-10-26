import SwiftUI

/// Shared shape metrics. Cards, filter chips and other containers use the same
/// continuous corner radius so the app reads as one family of surfaces.
enum DuovaMetrics {
    static let cornerRadius: CGFloat = 16
    static let screenMargin: CGFloat = 16
    static let gridSpacing: CGFloat = 12
}

/// Which accent family the interface uses. `duova` is the signature
/// blue–indigo–purple look; `mono` is a restrained black-and-white variant.
/// Third-party service icons always keep their own colors.
enum DuovaColorStyle: String, CaseIterable, Identifiable, Codable {
    case duova
    case mono

    var id: String { rawValue }

    var title: String {
        switch self {
        case .duova: String(localized: "Duova")
        case .mono: String(localized: "Black & White")
        }
    }
}

/// Semantic colors for one appearance and color style. Views read the active
/// theme from the environment (`@Environment(\.duovaTheme)`), which
/// `DuovaThemeInjector` derives from the system color scheme and the user's
/// color-style choice.
struct DuovaTheme: Equatable {
    let isDark: Bool
    let style: DuovaColorStyle
    let background: Color
    let surface: Color
    let surfaceSecondary: Color
    let card: Color
    let border: Color
    let textPrimary: Color
    let textSecondary: Color
    /// Opacity of the ambient background glows.
    let glowOpacity: Double

    /// Primary interactive color (selection, prominent buttons, links).
    let accent: Color
    /// Content color that stays readable on top of `accent`.
    let onAccent: Color
    /// Gradient stops for brand surfaces such as avatars and highlights.
    let accentColors: [Color]
    /// The three ambient glow colors used by `DuovaBackdrop`.
    let glowColors: [Color]
    /// Destructive / error color.
    let danger: Color
    /// Positive / success color.
    let success: Color

    var brandGradient: LinearGradient {
        LinearGradient(colors: accentColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Which rendering of the Duova icon matches this theme.
    var markStyle: DuovaMarkStyle {
        switch (style, isDark) {
        case (.duova, true): .dark
        case (.duova, false): .light
        case (.mono, true): .mono
        case (.mono, false): .monoLight
        }
    }

    /// Tint for a compatibility status. Black & White keeps statuses neutral.
    func tint(for status: CompatibilityStatus) -> Color {
        style == .duova ? status.tint : textSecondary
    }

    init(_ scheme: ColorScheme, style: DuovaColorStyle = .duova) {
        let dark = scheme == .dark
        isDark = dark
        self.style = style
        danger = dark ? Color(hex: 0xE5738C) : Color(hex: 0xB23A56)
        success = dark ? Color(hex: 0x6CBF8E) : Color(hex: 0x2E7D52)

        switch style {
        case .duova:
            if dark {
                background = Color(hex: 0x050508)
                surface = Color(hex: 0x0B0B10)
                surfaceSecondary = Color(hex: 0x111117)
                card = Color(hex: 0x14141C, opacity: 0.76)
                border = Color.white.opacity(0.10)
                textPrimary = Color(hex: 0xF5F7FF)
                textSecondary = Color(hex: 0xA3A9BA)
                glowOpacity = 0.14
            } else {
                background = Color(hex: 0xF7F9FC)
                surface = Color(hex: 0xFFFFFF)
                surfaceSecondary = Color(hex: 0xEEF2F8)
                card = Color.white.opacity(0.82)
                border = Color(hex: 0x0F172A, opacity: 0.08)
                textPrimary = Color(hex: 0x0F172A)
                textSecondary = Color(hex: 0x475569)
                glowOpacity = 0.10
            }
            accent = DuovaPalette.blue
            onAccent = .white
            accentColors = DuovaPalette.brandColors
            glowColors = [DuovaPalette.blue, DuovaPalette.purple, DuovaPalette.indigo]

        case .mono:
            if dark {
                background = Color(hex: 0x000000)
                surface = Color(hex: 0x0A0A0A)
                surfaceSecondary = Color(hex: 0x141414)
                card = Color(hex: 0x141414, opacity: 0.76)
                border = Color.white.opacity(0.12)
                textPrimary = Color(hex: 0xFFFFFF)
                textSecondary = Color(hex: 0xA1A1A6)
                accent = Color(hex: 0xF2F2F7)
                onAccent = Color(hex: 0x0A0A0A)
                accentColors = [Color(hex: 0xFFFFFF), Color(hex: 0x8E8E93)]
                glowColors = [Color.white, Color(hex: 0x8E8E93), Color(hex: 0x636366)]
                glowOpacity = 0.07
            } else {
                background = Color(hex: 0xFFFFFF)
                surface = Color(hex: 0xFFFFFF)
                surfaceSecondary = Color(hex: 0xF2F2F7)
                card = Color.white.opacity(0.85)
                border = Color.black.opacity(0.10)
                textPrimary = Color(hex: 0x0A0A0A)
                textSecondary = Color(hex: 0x5C5C61)
                accent = Color(hex: 0x111114)
                onAccent = .white
                accentColors = [Color(hex: 0x3A3A3F), Color(hex: 0x0A0A0A)]
                glowColors = [Color(hex: 0x8E8E93), Color(hex: 0xAEAEB2), Color(hex: 0xC7C7CC)]
                glowOpacity = 0.10
            }
        }
    }

    static let dark = DuovaTheme(.dark)
    static let light = DuovaTheme(.light)
}

private struct DuovaThemeKey: EnvironmentKey {
    static let defaultValue = DuovaTheme.dark
}

extension EnvironmentValues {
    var duovaTheme: DuovaTheme {
        get { self[DuovaThemeKey.self] }
        set { self[DuovaThemeKey.self] = newValue }
    }
}

/// Publishes the Duova theme matching the current color scheme and style.
struct DuovaThemeInjector: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let style: DuovaColorStyle

    func body(content: Content) -> some View {
        content.environment(\.duovaTheme, DuovaTheme(colorScheme, style: style))
    }
}

extension View {
    /// Applies the Duova theme for the current color scheme to this hierarchy.
    func duovaTheme(style: DuovaColorStyle = .duova) -> some View {
        modifier(DuovaThemeInjector(style: style))
    }
}

/// Full-bleed Duova background: base color plus two soft ambient glows.
struct DuovaBackdrop: View {
    @Environment(\.duovaTheme) private var theme
    /// 0...1 multiplier for the glows (the base color is always fully drawn).
    var intensity: Double = 1

    var body: some View {
        GeometryReader { geo in
            let reach = max(geo.size.width, geo.size.height)
            ZStack {
                theme.background
                RadialGradient(
                    colors: [theme.glowColors[0].opacity(theme.glowOpacity * intensity), .clear],
                    center: UnitPoint(x: 0.12, y: 0.10),
                    startRadius: 0,
                    endRadius: reach * 0.6
                )
                RadialGradient(
                    colors: [theme.glowColors[1].opacity(theme.glowOpacity * intensity), .clear],
                    center: UnitPoint(x: 0.90, y: 0.92),
                    startRadius: 0,
                    endRadius: reach * 0.6
                )
                RadialGradient(
                    colors: [theme.glowColors[2].opacity(theme.glowOpacity * 0.45 * intensity), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: reach * 0.45
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
