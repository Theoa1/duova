import SwiftUI

// MARK: - App Preferences (list of services)

/// Searchable list of services. Compact widths push one settings page at a
/// time; wide widths show the list and the selected service's settings side by side.
struct AppPreferencesPage: View {
    @Environment(\.duovaTheme) private var theme
    @Environment(ServicePreferences.self) private var prefs

    @State private var query = ""
    @State private var selected: ServiceID?

    private var results: [Service] {
        ServiceCatalog.all.filter { $0.matches(query) }
    }

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= 720 {
                wide
            } else {
                compact
            }
        }
        .background { DuovaBackdrop() }
        .navigationTitle("App Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search apps")
    }

    // MARK: Compact

    private var compact: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                intro
                if results.isEmpty {
                    ContentUnavailableView.search(text: query).padding(.top, 24)
                } else {
                    SettingsGroup {
                        ForEach(results) { service in
                            NavigationLink(value: ProfileDestination.service(service.id)) {
                                ServicePreferenceRow(service: service, showsChevron: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, DuovaMetrics.screenMargin)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Wide

    private var wide: some View {
        let current = selected.flatMap { id in results.first { $0.id == id } } ?? results.first
        return HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    intro
                    if results.isEmpty {
                        ContentUnavailableView.search(text: query).padding(.top, 24)
                    } else {
                        SettingsGroup {
                            ForEach(results) { service in
                                Button {
                                    selected = service.id
                                } label: {
                                    ServicePreferenceRow(service: service, showsChevron: false)
                                        .background(
                                            service.id == current?.id
                                                ? theme.accent.opacity(0.14) : Color.clear)
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(service.id == current?.id ? .isSelected : [])
                            }
                        }
                    }
                }
                .padding(DuovaMetrics.screenMargin)
            }
            .scrollIndicators(.hidden)
            .frame(width: 340)

            Divider()

            if let current {
                ScrollView {
                    ServicePreferencesContent(service: current)
                        .frame(maxWidth: 560)
                        .padding(DuovaMetrics.screenMargin)
                        .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .id(current.id)
            } else {
                Color.clear.frame(maxWidth: .infinity)
            }
        }
    }

    private var intro: some View {
        Text("Choose an app to customize it. Anything you leave on Duova default follows your global settings.")
            .font(.footnote)
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 6)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ServicePreferenceRow: View {
    @Environment(\.duovaTheme) private var theme
    @Environment(ServicePreferences.self) private var prefs
    let service: Service
    let showsChevron: Bool

    var body: some View {
        let count = prefs.overrideCount(for: service.id)
        HStack(spacing: 12) {
            ServiceIcon(id: service.id, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .font(.body)
                    .foregroundStyle(theme.textPrimary)
                Text(count == 0 ? "Duova defaults" : "\(count) custom")
                    .font(.caption)
                    .foregroundStyle(count == 0 ? theme.textSecondary : theme.accent)
            }
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.textSecondary.opacity(0.7))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - One service

struct ServicePreferencesPage: View {
    let service: Service

    var body: some View {
        SettingsPage(title: LocalizedStringKey(service.name)) {
            ServicePreferencesContent(service: service)
        }
    }
}

/// Every control here changes only this service. A field left on "Duova
/// default" inherits the global value, so later changes to the default still reach it.
struct ServicePreferencesContent: View {
    @Environment(\.duovaTheme) private var theme
    @Environment(ServicePreferences.self) private var prefs
    @Environment(DisplayPreferences.self) private var display

    let service: Service
    @State private var confirmReset = false

    private func binding<Value>(_ keyPath: WritableKeyPath<ServiceOverrides, Value?>) -> Binding<Value?> {
        Binding(
            get: { prefs.overrides(for: service.id)[keyPath: keyPath] },
            set: { newValue in prefs.update(service.id) { $0[keyPath: keyPath] = newValue } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                ServiceIcon(id: service.id, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(service.category.longTitle)
                        .font(.footnote)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            SettingsGroup(title: "Look & feel") {
                OverrideRow(title: "Appearance", global: display.appearance, override: binding(\.appearance))
                OverrideRow(title: "Animation", global: display.motion, override: binding(\.motion))
            }

            SettingsGroup(title: "Layout") {
                OverrideRow(title: "Expanded layout", global: prefs.defaults.expandedLayout, override: binding(\.expandedLayout))
                OverrideRow(title: "Panel ratio", global: prefs.defaults.panelRatio, override: binding(\.panelRatio))
                OverrideRow(title: "Opening behavior", global: prefs.defaults.opening, override: binding(\.opening))
            }

            SettingsGroup(title: "Controls") {
                OverrideRow(title: "Floating switcher", global: prefs.defaults.switcherSide, override: binding(\.switcherSide))
                OverrideRow(title: "Gesture", global: prefs.defaults.gesture, override: binding(\.gesture))
            }

            SettingsGroup(
                footer: "Changes apply only to \(service.name). Reset returns every setting here to Duova's defaults."
            ) {
                SettingsButtonRow(symbol: "arrow.counterclockwise", title: "Reset to Duova Defaults") {
                    confirmReset = true
                }
                .disabled(prefs.overrideCount(for: service.id) == 0)
            }
        }
        .confirmationDialog("Reset \(service.name)?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset to Duova Defaults", role: .destructive) { prefs.reset(service.id) }
        } message: {
            Text("\(service.name) will follow your global settings again.")
        }
    }
}

/// Menu row whose first choice is "Duova default", which keeps inheritance.
private struct OverrideRow<Option: MenuOption>: View {
    @Environment(\.duovaTheme) private var theme
    let title: LocalizedStringKey
    let global: Option
    @Binding var override: Option?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(theme.textPrimary)
                if override == nil {
                    Text("Duova default: \(global.title)")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            Menu {
                Picker(selection: $override) {
                    Text("Duova default (\(global.title))").tag(Option?.none)
                    ForEach(Option.allCases) { option in
                        Text(option.title).tag(Option?.some(option))
                    }
                } label: { Text(title) }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 4) {
                    if let override {
                        Circle().fill(theme.accent).frame(width: 6, height: 6)
                        Text(override.title).foregroundStyle(theme.textPrimary)
                    } else {
                        Text("Default").foregroundStyle(theme.textSecondary)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(theme.textSecondary)
                }
                .font(.body)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Duo layouts (global defaults)

struct DuoLayoutsPage: View {
    @Environment(ServicePreferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        SettingsPage(title: "Duo Layouts") {
            SettingsGroup(
                title: "Defaults",
                footer: "These are Duova's defaults for every app. You can change any of them for one app in App Preferences."
            ) {
                SettingsMenuRow(symbol: "rectangle.expand.vertical", title: "Expanded layout",
                                selection: $prefs.defaults.expandedLayout)
                SettingsMenuRow(symbol: "rectangle.split.2x1.fill", title: "Panel ratio",
                                selection: $prefs.defaults.panelRatio)
                SettingsMenuRow(symbol: "arrow.uturn.backward", title: "Opening behavior",
                                selection: $prefs.defaults.opening)
            }

            SettingsGroup(
                footer: "Adaptive uses two panes when there's room and one pane when the window is narrow. Two panes are always collapsed to one on a narrow screen."
            ) {
                SettingsValueRow(title: "Compact screens", value: String(localized: "Single pane"))
            }
        }
    }
}

// MARK: - Appearance & gestures

struct AppearanceGesturesPage: View {
    @Environment(\.duovaTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(DisplayPreferences.self) private var display
    @Environment(ServicePreferences.self) private var prefs

    var body: some View {
        @Bindable var display = display
        @Bindable var prefs = prefs
        SettingsPage(title: "Appearance & Gestures") {
            SettingsGroup(
                title: "Theme",
                footer: "System follows your device's light and dark setting."
            ) {
                HStack(spacing: 10) {
                    ForEach(AppearanceMode.allCases) { mode in
                        ThemeTile(
                            title: mode.title,
                            isSelected: display.appearance == mode
                        ) {
                            MiniScreenPreview(mode: mode, style: display.colorStyle, fallbackScheme: colorScheme)
                        } action: {
                            withAnimation(.easeInOut(duration: 0.25)) { display.appearance = mode }
                        }
                    }
                }
                .padding(12)
            }

            SettingsGroup(
                title: "Color style",
                footer: "Black & White replaces Duova's blue, indigo and purple with plain black and white. Service icons keep their own colors."
            ) {
                HStack(spacing: 10) {
                    ForEach(DuovaColorStyle.allCases) { style in
                        ThemeTile(
                            title: style.title,
                            isSelected: display.colorStyle == style
                        ) {
                            MiniScreenPreview(
                                mode: display.appearance == .system ? (colorScheme == .dark ? .dark : .light) : display.appearance,
                                style: style, fallbackScheme: colorScheme)
                        } action: {
                            withAnimation(.easeInOut(duration: 0.25)) { display.colorStyle = style }
                        }
                    }
                }
                .padding(12)
            }

            SettingsGroup(
                title: "Motion",
                footer: "Duova always follows Reduce Motion in iOS Settings, whatever you choose here."
            ) {
                SettingsMenuRow(symbol: "wind", title: "Animation intensity", selection: $display.motion)
            }

            SettingsGroup(
                title: "Controls",
                footer: "These are the defaults for every app. Override them for one app in App Preferences."
            ) {
                SettingsMenuRow(symbol: "sidebar.right", title: "Floating switcher",
                                selection: $prefs.defaults.switcherSide)
                SettingsMenuRow(symbol: "hand.draw.fill", title: "Gesture",
                                selection: $prefs.defaults.gesture)
            }
        }
    }
}

/// Selectable tile: a small preview above its name.
private struct ThemeTile<Preview: View>: View {
    @Environment(\.duovaTheme) private var theme
    let title: String
    let isSelected: Bool
    @ViewBuilder var preview: Preview
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview
                    .frame(height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSelected ? theme.accent : theme.border, lineWidth: isSelected ? 2 : 1)
                    )
                HStack(spacing: 4) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(theme.accent)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .font(.footnote.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A miniature of the interface in a given appearance and color style.
private struct MiniScreenPreview: View {
    let mode: AppearanceMode
    let style: DuovaColorStyle
    let fallbackScheme: ColorScheme

    var body: some View {
        switch mode {
        case .light: screen(DuovaTheme(.light, style: style))
        case .dark: screen(DuovaTheme(.dark, style: style))
        case .system:
            ZStack {
                screen(DuovaTheme(.light, style: style))
                screen(DuovaTheme(.dark, style: style))
                    .clipShape(RightHalf())
            }
        }
    }

    private func screen(_ theme: DuovaTheme) -> some View {
        ZStack(alignment: .topLeading) {
            theme.background
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(theme.brandGradient).frame(width: 34, height: 6)
                Capsule().fill(theme.textSecondary.opacity(0.55)).frame(width: 52, height: 4)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(theme.surfaceSecondary)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(theme.border, lineWidth: 0.5))
                    .frame(height: 14)
            }
            .padding(10)
        }
    }

    private struct RightHalf: Shape {
        func path(in rect: CGRect) -> Path {
            Path(CGRect(x: rect.midX, y: rect.minY, width: rect.width / 2, height: rect.height))
        }
    }
}
