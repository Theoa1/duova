import SwiftUI

/// Rounded-square profile picture, or a monogram on the theme's accent gradient.
/// The corners match the rest of the app; very small pictures round proportionally.
struct AvatarView: View {
    @Environment(\.duovaTheme) private var theme
    let initials: String
    var image: UIImage?
    var size: CGFloat = 72

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: min(DuovaMetrics.cornerRadius, size * 0.3), style: .continuous)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    shape.fill(theme.brandGradient)
                    Text(initials)
                        .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.onAccent)
                        .minimumScaleFactor(0.5)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(theme.isDark ? 0.22 : 0.5), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// Standard container shape for glass surfaces.
extension View {
    func duovaGlassCard() -> some View {
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: DuovaMetrics.cornerRadius, style: .continuous))
    }
}

/// Scrolling page used for every settings destination. Like the Apps page it
/// runs the full width of its space with a small margin, and splits into two
/// columns when there is room for them.
struct SettingsPage<Content: View>: View {
    @Environment(\.duovaTheme) private var theme
    let title: LocalizedStringKey
    /// Cards have no navigation bar, so they show the title at the top of the page.
    var showsTitle = false
    @ViewBuilder var content: Content
    @State private var width: CGFloat = 0

    init(title: LocalizedStringKey, showsTitle: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.showsTitle = showsTitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            if showsTitle {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DuovaMetrics.screenMargin)
                    .padding(.top, 20)
                    .padding(.trailing, 44)
                    .accessibilityAddTraits(.isHeader)
            }
            Group(subviews: content) { subviews in
                if width >= 700 {
                    HStack(alignment: .top, spacing: 20) {
                        column(subviews, parity: 0)
                        column(subviews, parity: 1)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(subviews.indices, id: \.self) { subviews[$0] }
                    }
                }
            }
            .padding(.horizontal, DuovaMetrics.screenMargin)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background { DuovaBackdrop() }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension SettingsPage {
    @ViewBuilder
    fileprivate func column(_ subviews: SubviewsCollection, parity: Int) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(subviews.indices.filter { $0 % 2 == parity }, id: \.self) { subviews[$0] }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

/// A titled group of rows on one glass card. Dividers are inserted between rows.
struct SettingsGroup<Content: View>: View {
    @Environment(\.duovaTheme) private var theme
    var title: LocalizedStringKey?
    var footer: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 6)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { subviews in
                    ForEach(subviews.indices, id: \.self) { index in
                        if index > 0 {
                            Divider().padding(.leading, 58)
                        }
                        subviews[index]
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .duovaGlassCard()

            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Small rounded-square symbol badge used at the leading edge of rows.
struct SettingsIcon: View {
    @Environment(\.duovaTheme) private var theme
    let symbol: String
    var tint: Color?

    var body: some View {
        // Just the symbol: no tinted tile behind it.
        Image(systemName: symbol)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(tint ?? theme.accent)
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)
    }
}

private struct RowLabel: View {
    @Environment(\.duovaTheme) private var theme
    let symbol: String?
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var tint: Color?
    var titleColor: Color?

    var body: some View {
        HStack(spacing: 12) {
            if let symbol { SettingsIcon(symbol: symbol, tint: tint) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(titleColor ?? theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
        }
    }
}

/// A row that pushes a destination.
struct SettingsLinkRow<Value: Hashable>: View {
    @Environment(\.duovaTheme) private var theme
    let symbol: String
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    let value: Value

    var body: some View {
        NavigationLink(value: value) {
            HStack(spacing: 8) {
                RowLabel(symbol: symbol, title: title, subtitle: subtitle)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.textSecondary.opacity(0.7))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A row that runs an action.
struct SettingsButtonRow: View {
    @Environment(\.duovaTheme) private var theme
    let symbol: String?
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RowLabel(
                symbol: symbol, title: title, subtitle: subtitle,
                tint: isDestructive ? theme.danger : nil,
                titleColor: isDestructive ? theme.danger : theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A read-only label / value row.
struct SettingsValueRow: View {
    @Environment(\.duovaTheme) private var theme
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundStyle(theme.textPrimary)
            Spacer(minLength: 12)
            Text(value)
                .font(.body)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsToggleRow: View {
    @Environment(\.duovaTheme) private var theme
    let symbol: String
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            RowLabel(symbol: symbol, title: title, subtitle: subtitle)
        }
        .tint(theme.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
    }
}

/// A row with a menu of named choices.
struct SettingsMenuRow<Option: MenuOption>: View {
    @Environment(\.duovaTheme) private var theme
    let symbol: String?
    let title: LocalizedStringKey
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 12) {
            RowLabel(symbol: symbol, title: title)
            Menu {
                Picker(selection: $selection) {
                    ForEach(Option.allCases) { option in
                        Text(option.title).tag(option)
                    }
                } label: { Text(title) }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 4) {
                    Text(selection.title)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .font(.body)
                .foregroundStyle(theme.textSecondary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}

/// Inline message shown under a form: an error, or neutral guidance.
struct FormMessage: View {
    enum Kind { case error, info, success }
    @Environment(\.duovaTheme) private var theme
    let text: String
    var kind: Kind = .info

    var body: some View {
        let color: Color = switch kind {
        case .error: theme.danger
        case .success: theme.success
        case .info: theme.textSecondary
        }
        let symbol: String = switch kind {
        case .error: "exclamationmark.circle.fill"
        case .success: "checkmark.circle.fill"
        case .info: "info.circle"
        }
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.footnote)
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// One input row inside a glass card: leading symbol, then the field.
struct FormFieldRow<Content: View>: View {
    @Environment(\.duovaTheme) private var theme
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(theme.textSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            content
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }
}

/// Full-width prominent action used at the bottom of forms.
struct ProminentActionButton: View {
    @Environment(\.duovaTheme) private var theme
    let title: LocalizedStringKey
    var isWorking = false
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isWorking {
                    ProgressView().tint(isDestructive ? .white : theme.onAccent)
                } else {
                    Text(title)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.roundedRectangle(radius: DuovaMetrics.cornerRadius))
        .controlSize(.large)
        .tint(isDestructive ? theme.danger : theme.accent)
        .foregroundStyle(isDestructive ? Color.white : theme.onAccent)
    }
}
