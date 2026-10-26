import SwiftUI

/// First screen after the launch sequence on a fresh install.
///
/// There is no account backend yet, so the only action offered is the one that
/// really works: entering the local library. Sign-in options will appear here
/// only once they are implemented (blueprint §4).
///
/// In compact-width layouts the icon and wordmark sit exactly where the launch
/// sequence leaves them, so the hand-off reads as one continuous moment.
struct WelcomeView: View {
    @Environment(\.duovaTheme) private var theme
    @Environment(AppSession.self) private var session

    var body: some View {
        GeometryReader { geo in
            let isWide = geo.size.width > geo.size.height * 1.1
            ZStack {
                DuovaBackdrop()
                ScrollView {
                    Group {
                        if isWide {
                            wideContent(size: geo.size)
                        } else {
                            tallContent(size: geo.size, insets: geo.safeAreaInsets)
                        }
                    }
                    // Wide content is centered; tall content is pinned to the top so
                    // the icon stays exactly where the launch sequence left it.
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: isWide ? .center : .top)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    // MARK: Layouts

    /// Portrait and other tall scenes: one centered column aligned with the launch screen.
    private func tallContent(size: CGSize, insets: EdgeInsets) -> some View {
        let full = CGSize(width: size.width + insets.leading + insets.trailing,
                          height: size.height + insets.top + insets.bottom)
        let g = LaunchGeometry(size: full, insets: insets)
        let heroTop = max(0, g.heroCenter.y - g.heroSize / 2 - insets.top)

        return VStack(spacing: 0) {
            Color.clear.frame(height: heroTop)
            DuovaMark(style: theme.isDark ? .dark : .light)
                .frame(width: g.heroSize, height: g.heroSize)
            DuovaLockup(scale: g.scale)
                .padding(.top, LaunchGeometry.baseGap * g.scale)
            description(alignment: .center)
                .padding(.top, 14)
                .frame(maxWidth: 460)
            actions(alignment: .center)
                .padding(.top, 28)
                .frame(maxWidth: 420)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity)
    }

    /// Landscape and other wide scenes: icon beside the copy so the button stays on screen.
    private func wideContent(size: CGSize) -> some View {
        let markSide = Motion.clamp(size.height * 0.36, 84, 168)
        return HStack(spacing: 48) {
            DuovaMark(style: theme.isDark ? .dark : .light)
                .frame(width: markSide, height: markSide)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Duova")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                    Text("Your apps. Reimagined.")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
                description(alignment: .leading)
                actions(alignment: .leading)
            }
            .frame(maxWidth: 460, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: 900)
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    // MARK: Pieces

    private func description(alignment: TextAlignment) -> some View {
        Text("One adaptive space for the services you use. Open anything. Stay in flow.")
            .font(.body)
            .foregroundStyle(theme.textPrimary.opacity(0.85))
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func actions(alignment: TextAlignment) -> some View {
        VStack(spacing: 16) {
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    session.completeWelcome()
                }
            } label: {
                Text("Get started")
            }
            .buttonStyle(DuovaPrimaryButtonStyle())

            Text("Duova is an independent product. Service names and logos belong to their owners and are shown for identification only; no partnership or endorsement is implied.")
                .font(.footnote)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(alignment)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Full-width capsule button filled with the brand gradient.
struct DuovaPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 20)
            .background(
                LinearGradient(
                    colors: [Color(hex: 0x3F72C4), Color(hex: 0x5B59B8), Color(hex: 0x8559B5)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

#Preview("Welcome") {
    WelcomeView()
        .environment(AppSession(defaults: UserDefaults(suiteName: "duova.preview") ?? .standard))
        .duovaTheme()
}
