import SwiftUI

/// The Duova launch experience.
///
/// App icons float in from the edges, converge on the Duova icon, and morph
/// into it before the wordmark appears. The sequence never gates app
/// readiness: it only runs for its fixed (short) duration, can be skipped with
/// a tap or the VoiceOver default action, and is simplified for Reduce Motion.
struct LaunchView: View {
    let variant: LaunchVariant
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate = Date()
    @State private var hasFinished = false

    var body: some View {
        let timeline = LaunchTimeline(variant: variant, reducesMotion: reduceMotion)

        GeometryReader { geo in
            // The reader respects the safe area; the scene draws under it so
            // the background reaches every edge while content stays inside.
            let insets = geo.safeAreaInsets
            let full = CGSize(
                width: geo.size.width + insets.leading + insets.trailing,
                height: geo.size.height + insets.top + insets.bottom
            )
            TimelineView(.animation) { context in
                LaunchScene(
                    timeline: timeline,
                    t: context.date.timeIntervalSince(startDate),
                    size: full,
                    insets: insets
                )
            }
            .frame(width: full.width, height: full.height)
            .offset(x: -insets.leading, y: -insets.top)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .contentShape(Rectangle())
        .onTapGesture(perform: finish)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Duova. Your apps. Reimagined."))
        .accessibilityHint(Text("Double-tap to skip the introduction."))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, finish)
        .task {
            try? await Task.sleep(for: .seconds(timeline.total))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        onFinish()
    }
}

#Preview("Full · dark") {
    LaunchView(variant: .full, onFinish: {})
        .duovaTheme()
        .environment(\.colorScheme, .dark)
}

#Preview("Quick · light") {
    LaunchView(variant: .quick, onFinish: {})
        .duovaTheme()
        .environment(\.colorScheme, .light)
}

#Preview("Resume") {
    LaunchView(variant: .resume, onFinish: {})
        .duovaTheme()
}
