import SwiftUI

// The building blocks every sign-in screen uses, so each step looks and reads
// the same: a title, one card of fields, live checks, messages, one main
// button, and small text links.

/// Title (and optional one-line explanation) at the top of an auth step.
struct AuthHeader: View {
    @Environment(\.duovaTheme) private var theme
    let title: LocalizedStringKey
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

/// One input strip inside the field card. Tapping anywhere on it focuses the field.
struct AuthFieldRow<Content: View>: View {
    @Environment(\.duovaTheme) private var theme
    let symbol: String
    let onTap: () -> Void
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
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

/// The hairline between rows of the field card, aligned with the text.
struct AuthFieldDivider: View {
    var body: some View { Divider().padding(.leading, 52) }
}

/// Eye button that shows or hides a password.
struct RevealPasswordButton: View {
    @Environment(\.duovaTheme) private var theme
    @Binding var isRevealed: Bool

    var body: some View {
        Button {
            isRevealed.toggle()
        } label: {
            Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                .foregroundStyle(theme.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
    }
}

/// A password field that can be revealed, used everywhere a password is typed.
struct PasswordInput: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    @Binding var isRevealed: Bool
    var isNew = false

    var body: some View {
        Group {
            if isRevealed {
                TextField(placeholder, text: $text)
            } else {
                SecureField(placeholder, text: $text)
            }
        }
        .textContentType(isNew ? .newPassword : .password)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }
}

/// A live rule under a password field: ticks green once it's met.
struct PasswordRule: View {
    @Environment(\.duovaTheme) private var theme
    let text: LocalizedStringKey
    let isMet: Bool

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
        }
        .font(.footnote)
        .foregroundStyle(isMet ? theme.success : theme.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isMet ? Text("Met") : Text("Not met"))
    }
}

/// The password rules: the length the server requires, and (when there's a
/// confirmation field) that both entries match.
struct PasswordRules: View {
    let password: String
    var confirmation: String?

    static func isSatisfied(_ password: String, confirmation: String? = nil) -> Bool {
        password.count >= PasswordPolicy.minimumLength
            && password.count <= PasswordPolicy.maximumLength
            && (confirmation.map { $0 == password } ?? true)
    }

    var body: some View {
        VStack(spacing: 6) {
            PasswordRule(
                text: "At least \(PasswordPolicy.minimumLength) characters",
                isMet: password.count >= PasswordPolicy.minimumLength)
            if let confirmation {
                PasswordRule(text: "Passwords match", isMet: !confirmation.isEmpty && confirmation == password)
            }
        }
    }
}

/// The success note and the error under a form.
struct AuthMessages: View {
    var notice: String?
    var error: String?

    var body: some View {
        if let notice {
            FormMessage(text: notice, kind: .success)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
        if let error {
            FormMessage(text: error, kind: .error)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }
}

/// The main action of an auth step.
struct AuthPrimaryButton: View {
    @Environment(\.duovaTheme) private var theme
    let title: LocalizedStringKey
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isWorking {
                    ProgressView().tint(theme.onAccent)
                } else {
                    Text(title)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.roundedRectangle(radius: DuovaMetrics.cornerRadius))
        .controlSize(.large)
        .tint(theme.accent)
        .foregroundStyle(theme.onAccent)
    }
}

/// A secondary, full-width glass button (for example "Enter confirmation code"
/// under an error).
struct AuthSecondaryButton: View {
    @Environment(\.duovaTheme) private var theme
    let title: LocalizedStringKey
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 24)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: DuovaMetrics.cornerRadius))
        .controlSize(.large)
        .foregroundStyle(theme.textPrimary)
    }
}

/// Text links along the bottom of a step, such as "Back" and "Resend code".
struct AuthLinkRow<Leading: View, Trailing: View>: View {
    @Environment(\.duovaTheme) private var theme
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            leading
            Spacer(minLength: 12)
            trailing
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(theme.accent)
        .frame(minHeight: 44)
        .padding(.horizontal, 4)
    }
}

/// A pill that picks where a code goes. A disabled choice explains why.
struct AuthChoiceChip: View {
    @Environment(\.duovaTheme) private var theme
    let title: LocalizedStringKey
    let symbol: String
    let isSelected: Bool
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 24)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .foregroundStyle(isSelected ? theme.accent : theme.textPrimary)
        .overlay {
            if isSelected {
                Capsule().strokeBorder(theme.accent, lineWidth: 1.5)
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
