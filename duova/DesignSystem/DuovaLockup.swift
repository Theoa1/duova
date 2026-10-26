import SwiftUI

/// The "Duova" wordmark with its tagline, shared by the launch screen and the
/// welcome screen so the two line up exactly during the hand-off.
struct DuovaLockup: View {
    @Environment(\.duovaTheme) private var theme
    @ScaledMetric(relativeTo: .largeTitle) private var wordmarkBase: CGFloat = 36
    @ScaledMetric(relativeTo: .subheadline) private var taglineBase: CGFloat = 15

    /// Layout scale (see `LaunchGeometry.scale`).
    var scale: CGFloat = 1
    var wordmarkOpacity: Double = 1
    var taglineOpacity: Double = 1

    var body: some View {
        VStack(spacing: 8 * scale) {
            Text("Duova")
                .font(.system(size: wordmarkBase * scale, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
                .opacity(wordmarkOpacity)
                .offset(y: CGFloat(1 - wordmarkOpacity) * 8 * scale)
            Text("Your apps. Reimagined.")
                .font(.system(size: taglineBase * scale, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .opacity(taglineOpacity)
                .offset(y: CGFloat(1 - taglineOpacity) * 6 * scale)
        }
        .multilineTextAlignment(.center)
    }
}
