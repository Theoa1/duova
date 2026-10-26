import AuthenticationServices
import SwiftUI

/// Sign in or sign up on one short, minimal screen: Sign in with Apple, a
/// passkey, and the email form, with a link to switch between "Sign in" and
/// "Sign up". In portrait the Terms open as a sheet; when the window has a
/// side page (book view or landscape), the Terms fill it, and its checkbox and
/// the one under the form are the same setting.
///
/// Creating an account by email or passkey requires accepting the Terms of
/// Use. On devices with Touch ID or Face ID, a toggle saves the sign-in behind
/// it, and a saved sign-in adds a biometric button beside the main one.
///
/// Shown on first use and after sign-out. Returning users with a valid session
/// never see it.
struct SignInView: View {
    private enum Field: Hashable { case email, password }

    @Environment(\.duovaTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AuthController.self) private var auth

    @State private var intent: AuthIntent = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var acceptedTerms = false
    @State private var rememberWithBiometrics = false
    @State private var showTerms = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private var kind: BiometricKind { auth.biometricKind }
    private var isSignUp: Bool { intent == .signUp }
    private var emailIsValid: Bool { EmailNormalizer.isValid(EmailNormalizer.normalize(email)) }
    private var meetsLength: Bool { password.count >= PasswordPolicy.minimumLength }
    /// Creating an account needs the Terms accepted first.
    private var termsSatisfied: Bool { !isSignUp || acceptedTerms }

    private var canSubmit: Bool {
        guard emailIsValid, !password.isEmpty, !auth.isWorking, termsSatisfied else { return false }
        return isSignUp ? meetsLength : true
    }

    var body: some View {
        AuthScaffold(brandInPortrait: false) {
            TermsPanel(accepted: $acceptedTerms)
        } panel: { proxy in
            form
                .id("authForm")
                .revealOnFocus($focus, in: proxy, id: "authForm")
        }
        .pageSheet(isPresented: $showTerms) { TermsView() }
    }

    // MARK: Form

    private var form: some View {
        VStack(spacing: 12) {
            Text(isSignUp ? "Sign up" : "Sign in")
                .font(.title2.weight(.bold))
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)

            appleButton
            passkeyButton

            HStack(spacing: 12) {
                line
                Text("or")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
                line
            }
            .padding(.vertical, 2)
            .accessibilityHidden(true)

            fields

            if isSignUp {
                Label {
                    Text("At least \(PasswordPolicy.minimumLength) characters")
                } icon: {
                    Image(systemName: meetsLength ? "checkmark.circle.fill" : "circle")
                }
                .font(.footnote)
                .foregroundStyle(meetsLength ? theme.success : theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

                termsRow
            }

            if kind.isBiometric && !auth.biometricSignInReady {
                Toggle(isOn: $rememberWithBiometrics) {
                    Label("Use \(kind.title) next time", systemImage: kind.systemImage)
                        .font(.subheadline)
                        .foregroundStyle(theme.textPrimary)
                }
                .tint(theme.accent)
                .frame(minHeight: 44)
                .padding(.horizontal, 4)
            }

            if let errorMessage {
                FormMessage(text: errorMessage, kind: .error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            submitRow

            HStack(spacing: 6) {
                Text(isSignUp ? "Have an account?" : "New?")
                    .foregroundStyle(theme.textSecondary)
                Button(isSignUp ? "Sign in" : "Sign up", action: switchIntent)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.accent)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, minHeight: 44)

            if !isSignUp {
                Button {
                    showTerms = true
                } label: {
                    Text("Continuing with Apple accepts the \(Text("Terms of Use").underline())")
                }
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
                .buttonStyle(.plain)
            }
        }
        .onChange(of: email) { _, _ in errorMessage = nil }
        .onChange(of: password) { _, _ in errorMessage = nil }
        .onChange(of: acceptedTerms) { _, _ in errorMessage = nil }
    }

    private var line: some View {
        Rectangle().fill(theme.border).frame(height: 1)
    }

    // MARK: Apple and passkey

    private var appleButton: some View {
        SignInWithAppleButton(isSignUp ? .signUp : .signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            handleApple(result)
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: DuovaMetrics.cornerRadius, style: .continuous))
        .opacity(termsSatisfied ? 1 : 0.45)
        .allowsHitTesting(termsSatisfied && !auth.isWorking)
        .accessibilityHint(termsSatisfied ? Text("") : Text("Accept the Terms of Use first."))
    }

    private var passkeyButton: some View {
        Button(action: usePasskey) {
            Label(isSignUp ? "Sign up with a passkey" : "Sign in with a passkey",
                  systemImage: "person.badge.key.fill")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: DuovaMetrics.cornerRadius))
        .controlSize(.large)
        .foregroundStyle(theme.textPrimary)
        .disabled(!termsSatisfied || auth.isWorking)
    }

    // MARK: Email form

    private var fields: some View {
        VStack(spacing: 0) {
            fieldRow(symbol: "envelope.fill", field: .email) {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .email)
                    .onSubmit { focus = .password }
            }
            Divider().padding(.leading, 52)
            fieldRow(symbol: "lock.fill", field: .password) {
                Group {
                    if showPassword {
                        TextField("Password", text: $password)
                    } else {
                        SecureField("Password", text: $password)
                    }
                }
                .textContentType(isSignUp ? .newPassword : .password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($focus, equals: .password)
                .onSubmit(submit)

                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showPassword ? "Hide password" : "Show password")
            }
        }
        .duovaGlassCard()
    }

    /// The whole strip focuses its field, not only the text itself.
    private func fieldRow<Content: View>(
        symbol: String, field: Field, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(theme.textSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            content()
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .onTapGesture { focus = field }
    }

    private var termsRow: some View {
        HStack(spacing: 4) {
            Button {
                acceptedTerms.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: acceptedTerms ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(acceptedTerms ? theme.accent : theme.textSecondary)
                    Text("I agree to the")
                        .foregroundStyle(theme.textPrimary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("I agree to the Terms of Use"))
            .accessibilityAddTraits(acceptedTerms ? .isSelected : [])

            Button("Terms of Use") { showTerms = true }
                .fontWeight(.semibold)
                .foregroundStyle(theme.accent)
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .padding(.horizontal, 4)
    }

    private var submitRow: some View {
        HStack(spacing: 10) {
            Button(action: submit) {
                Group {
                    if auth.isWorking {
                        ProgressView().tint(theme.onAccent)
                    } else {
                        Text(isSignUp ? "Create account" : "Sign in")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: DuovaMetrics.cornerRadius))
            .controlSize(.large)
            .tint(theme.accent)
            .foregroundStyle(theme.onAccent)
            .disabled(!canSubmit)

            if !isSignUp && auth.biometricSignInReady {
                Button(action: signInWithBiometrics) {
                    Image(systemName: kind.systemImage)
                        .font(.title3)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: DuovaMetrics.cornerRadius))
                .controlSize(.large)
                .disabled(auth.isWorking)
                .accessibilityLabel(Text("Sign in with \(kind.title)"))
            }
        }
    }

    // MARK: Actions

    private func switchIntent() {
        withAnimation(.easeInOut(duration: 0.2)) {
            intent = isSignUp ? .signIn : .signUp
            errorMessage = nil
        }
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        errorMessage = nil
        let remember = rememberWithBiometrics
        Task {
            do {
                _ = try await auth.submit(
                    email: email, password: password, intent: intent,
                    acceptedTerms: acceptedTerms, rememberWithBiometrics: remember)
                password = ""
            } catch {
                report(error)
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        errorMessage = nil
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                present(String(localized: "Sign in with Apple didn't complete. Try again."))
                return
            }
            do {
                try auth.signInWithApple(
                    userID: credential.user, email: credential.email, fullName: credential.fullName)
            } catch {
                report(error)
            }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            present(String(localized: "Sign in with Apple isn't available right now."))
        }
    }

    private func usePasskey() {
        errorMessage = nil
        if isSignUp && !emailIsValid {
            present(String(localized: "Enter your email first, then sign up with a passkey."))
            focus = .email
            return
        }
        focus = nil
        Task {
            do {
                if isSignUp {
                    try await auth.signUpWithPasskey(email: email, acceptedTerms: acceptedTerms)
                } else {
                    try await auth.signInWithPasskey()
                }
            } catch {
                report(error)
            }
        }
    }

    private func signInWithBiometrics() {
        focus = nil
        errorMessage = nil
        Task {
            switch await auth.signInWithBiometrics() {
            case .success, .cancelled:
                break
            case .unavailable:
                present(String(localized: "\(kind.title) isn't set up. Use your password."))
            case .failed(let reason):
                present(reason)
            }
        }
    }

    private func report(_ error: Error) {
        if error is CancellationError { return }
        if let error = error as? AuthError {
            present(error.errorDescription ?? String(localized: "Something went wrong. Try again."))
        } else {
            present(String(localized: "Something went wrong. Try again."))
        }
    }

    private func present(_ message: String) {
        errorMessage = message
        AccessibilityNotification.Announcement(message).post()
    }
}

#Preview("Sign in") {
    SignInView()
        .environment(AuthController(store: SecureStore(directory: URL.temporaryDirectory.appending(path: "duova-preview"), keyService: "com.duova.preview")))
        .duovaTheme()
}
