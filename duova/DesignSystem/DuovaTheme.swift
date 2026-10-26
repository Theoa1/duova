import SwiftUI

/// Semantic colors for one appearance. Views read the active theme from the
/// environment (`@Environment(\.duovaTheme)`), which `DuovaThemeInjector`
/// derives from the system color scheme.
struct DuovaTheme: Equatable {
    let isDark: Bool
    let background: Color
    let surface: Color
    let surfaceSecondary: Color
    let card: Color
    let border: Color
    let textPrimary: Color
    let textSecondary: Color
    /// Opacity of the ambient background glows.
    let glowOpacity: Double

    var brandGradient: LinearGradient {
        LinearGradient(
            colors: DuovaPalette.brandColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static let dark = DuovaTheme(
        isDark: true,
        background: Color(hex: 0x050508),
        surface: Color(hex: 0x0B0B10),
        surfaceSecondary: Color(hex: 0x111117),
        card: Color(hex: 0x14141C, opacity: 0.76),
        border: Color.white.opacity(0.10),
        textPrimary: Color(hex: 0xF5F7FF),
        textSecondary: Color(hex: 0xA3A9BA),
        glowOpacity: 0.14
    )

    static let light = DuovaTheme(
        isDark: false,
        background: Color(hex: 0xF7F9FC),
        surface: Color(hex: 0xFFFFFF),
        surfaceSecondary: Color(hex: 0xEEF2F8),
        card: Color.white.opacity(0.82),
        border: Color(hex: 0x0F172A, opacity: 0.08),
        textPrimary: Color(hex: 0x0F172A),
        textSecondary: Color(hex: 0x475569),
        glowOpacity: 0.10
    )

    init(isDark: Bool, background: Color, surface: Color, surfaceSecondary: Color,
         card: Color, border: Color, textPrimary: Color, textSecondary: Color,
         glowOpacity: Double) {
        self.isDark = isDark
        self.background = background
        self.surface = surface
        self.surfaceSecondary = surfaceSecondary
        self.card = card
        self.border = border
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.glowOpacity = glowOpacity
    }

    init(_ scheme: ColorScheme) {
        self = scheme == .dark ? .dark : .light
    }
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

/// Publishes the Duova theme matching the current color scheme.
struct DuovaThemeInjector: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.environment(\.duovaTheme, DuovaTheme(colorScheme))
    }
}

extension View {
    /// Applies the Duova theme for the current color scheme to this hierarchy.
    func duovaTheme() -> some View {
        modifier(DuovaThemeInjector())
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
                    colors: [DuovaPalette.blue.opacity(theme.glowOpacity * intensity), .clear],
                    center: UnitPoint(x: 0.12, y: 0.10),
                    startRadius: 0,
                    endRadius: reach * 0.6
                )
                RadialGradient(
                    colors: [DuovaPalette.purple.opacity(theme.glowOpacity * intensity), .clear],
                    center: UnitPoint(x: 0.90, y: 0.92),
                    startRadius: 0,
                    endRadius: reach * 0.6
                )
                RadialGradient(
                    colors: [DuovaPalette.indigo.opacity(theme.glowOpacity * 0.45 * intensity), .clear],
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
