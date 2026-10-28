import SwiftUI

/// Duova's Terms of Use, shown in-app. Each point describes how the app
/// actually behaves today.
struct TermsView: View {
    var body: some View {
        SettingsPage(title: "Terms of Use", showsTitle: true) {
            TermsSections()
        }
    }
}

/// The Terms on a page of their own, with the accept checkbox at the end. Used
/// as the side page when the sign-in screen has two halves (book view or
/// landscape). The checkbox shares its state with the one under the form.
struct TermsPanel: View {
    @Environment(\.duovaTheme) private var theme
    @Binding var accepted: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Terms of Use")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                TermsSections()

                TermsCheckbox(accepted: $accepted)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// "I agree to the Terms of Use" checkbox.
struct TermsCheckbox: View {
    @Environment(\.duovaTheme) private var theme
    @Binding var accepted: Bool

    var body: some View {
        Button {
            accepted.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: accepted ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(accepted ? theme.accent : theme.textSecondary)
                Text("I agree to the Terms of Use")
                    .font(.subheadline)
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(accepted ? .isSelected : [])
    }
}

/// The Terms text itself.
struct TermsSections: View {
    @Environment(\.duovaTheme) private var theme

    private let sections: [(LocalizedStringKey, LocalizedStringKey)] = [
        ("Your Duova account",
         "Your Duova account lets you use Duova on this device. It is separate from your accounts on the services you open in Duova, which stay governed by those services' own terms."),
        ("Your data",
         "Your account details, profile photo, favorites and preferences are stored on this device, encrypted with AES-256. Your password is never stored, only a salted one-way hash. Duova doesn't sell your data."),
        ("Signing in",
         "You can sign in with your email and password, Sign in with Apple, or a passkey. Keep your password and devices secure; you're responsible for activity on your account."),
        ("Other services",
         "Service names and logos belong to their owners and are shown for identification only. Duova is an independent product and isn't affiliated with, sponsored by or endorsed by them."),
        ("Deleting your account",
         "You can delete your account at any time in Profile > Personal Information. This permanently erases everything Duova stores for it on this device."),
        ("Changes",
         "If these terms change, Duova will ask you to review them before you continue.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.0)
                        .font(.headline)
                        .foregroundStyle(theme.textPrimary)
                    Text(section.1)
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
