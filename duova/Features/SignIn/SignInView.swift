import AuthenticationServices
import SwiftUI

/// Everything before someone is signed in, as a few short steps on one screen:
///
/// - **Sign in / Sign up:** Sign in with Apple, a passkey, and email + password.
/// - **Forgot password:** email → code → new password.
/// - **Sign in with a code:** email (or phone, once texting is set up) → code.
/// - **Enter code:** confirms a new account's email, signs in with a code,
///   creates a passkey account, or finishes a password reset.
///
/// Each step uses the same parts (`AuthComponents`): a title, one card of
/// fields, live password rules, short messages, one main button, text links.
/// When an error has an obvious next step ("Confirm your email first"), a
/// button for it appears right under the message.
///
/// The Terms fill the second page only when the device is open (book view, in
/// either orientation). Closed, in portrait or landscape, the form fills the
/// whole screen and the Terms open as a sheet; both checkboxes are the same
/// setting.
/// One-time codes are only held in this view's memory and are never saved.
struct SignInView: View {
    private enum Screen: Equatable {
        case main
        case forgotPassword
        case codeSignIn
        case enterCode(EmailCodePurpose, CodeChannel)
    }

    private enum Field: Hashable { case email, phone, password, code, newPassword, confirmPassword }

    @Environment(\.duovaTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AuthController.self) private var auth

    @State private var screen: Screen = .main
    @State private var intent: AuthIntent = .signIn
    @State private var email = ""
    @State private var phone = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var acceptedTerms = false
    @State private var rememberWithBiometrics = false
    @State private var showTerms = false
    @State private var errorMessage: String?
    /// The error behind `errorMessage`, so a follow-up action can be offered.
    @State private var lastError: AuthError?
    @State private var notice: String?
    /// The raw nonce for the Sign in with Apple request in flight.
    @State private var appleNonce = ""
    @State private var codeChannel: CodeChannel = .email
    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    /// The password chosen at sign-up, held in memory until the email is confirmed.
    @State private var pendingPassword: String?
    @State private var resendAvailableAt = Date.distantPast
    @FocusState private var focus: Field?

    private var kind: BiometricKind { auth.biometricKind }
    private var isSignUp: Bool { intent == .signUp }
    private var normalizedEmail: String { EmailNormalizer.normalize(email) }
    private var emailIsValid: Bool { EmailNormalizer.isValid(normalizedEmail) }
    private var phoneIsValid: Bool { PhoneNormalizer.isValid(PhoneNormalizer.normalize(phone)) }
    private var meetsLength: Bool { password.count >= PasswordPolicy.minimumLength }
    /// Creating an account needs the Terms accepted first.
    private var termsSatisfied: Bool { !isSignUp || acceptedTerms }
    /// A passkey button only appears where it can work.
    private var showsPasskey: Bool {
        isSignUp ? auth.passkeySignUpAvailable : auth.passkeySignInAvailable
    }

    private var canSubmit: Bool {
        guard emailIsValid, !password.isEmpty, !auth.isWorking, termsSatisfied else { return false }
        return isSignUp ? PasswordRules.isSatisfied(password) : true
    }

    var body: some View {
        AuthScaffold(brandInPortrait: false, splitsWhenClosed: false) {
            TermsPanel(accepted: $acceptedTerms)
        } panel: { proxy in
            content
                .id("authForm")
                .revealOnFocus($focus, in: proxy, id: "authForm")
                .animation(.easeInOut(duration: 0.2), value: screen)
        }
        .pageSheet(isPresented: $showTerms) { TermsView() }
        .onAppear {
            if let resetEmail = auth.consumeResetRequest(), !resetEmail.isEmpty {
                email = resetEmail
                go(to: .forgotPassword)
            }
        }
        .onChange(of: email) { _, _ in clearError() }
        .onChange(of: phone) { _, _ in clearError() }
        .onChange(of: password) { _, _ in clearError() }
        .onChange(of: acceptedTerms) { _, _ in clearError() }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .main: mainStep
        case .forgotPassword: forgotPasswordStep
        case .codeSignIn: codeSignInStep
        case .enterCode(let purpose, let channel): enterCodeStep(purpose, channel)
        }
    }

    // MARK: - Sign in / Sign up

    private var mainStep: some View {
        VStack(spacing: 12) {
            AuthHeader(title: isSignUp ? "Sign up" : "Sign in")

            if auth.appleSignInAvailable { appleButton }
            if showsPasskey { passkeyButton }

            if auth.appleSignInAvailable || showsPasskey {
                HStack(spacing: 12) {
                    line
                    Text("or")
                        .font(.footnote)
                        .foregroundStyle(theme.textSecondary)
                    line
                }
                .padding(.vertical, 2)
                .accessibilityHidden(true)
            }

            VStack(spacing: 0) {
                emailRow(submit: { focus = .password })
                AuthFieldDivider()
                AuthFieldRow(symbol: "lock.fill", onTap: { focus = .password }) {
                    PasswordInput(
                        placeholder: "Password", text: $password, isRevealed: $showPassword, isNew: isSignUp)
                        .submitLabel(.go)
                        .focused($focus, equals: .password)
                        .onSubmit(submit)
                    RevealPasswordButton(isRevealed: $showPassword)
                }
            }
            .duovaGlassCard()

            if isSignUp {
                PasswordRules(password: password)
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

            AuthMessages(notice: notice, error: errorMessage)
            followUp

            submitRow

            if !isSignUp && auth.emailCodesAvailable {
                AuthLinkRow {
                    Button("Forgot password?") { go(to: .forgotPassword) }
                } trailing: {
                    Button("Sign in with a code") { go(to: .codeSignIn) }
                }
                .disabled(auth.isWorking)
            }

            HStack(spacing: 6) {
                Text(isSignUp ? "Have an account?" : "New?")
                    .foregroundStyle(theme.textSecondary)
                Button(isSignUp ? "Sign in" : "Sign up", action: switchIntent)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.accent)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, minHeight: 44)

            if !isSignUp && auth.appleSignInAvailable {
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
    }

    private var line: some View {
        Rectangle().fill(theme.border).frame(height: 1)
    }

    private var appleButton: some View {
        SignInWithAppleButton(isSignUp ? .signUp : .signIn) { request in
            request.requestedScopes = [.fullName, .email]
            appleNonce = AppleNonce.makeRaw()
            request.nonce = AppleNonce.sha256(appleNonce)
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
            AuthPrimaryButton(title: isSignUp ? "Create account" : "Sign in", isWorking: auth.isWorking, action: submit)
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

    /// The one obvious next step after an error, as a button.
    @ViewBuilder
    private var followUp: some View {
        switch lastError {
        case .emailNotConfirmed where auth.emailCodesAvailable:
            AuthSecondaryButton(title: "Enter confirmation code", symbol: "number") {
                pendingPassword = password.isEmpty ? nil : password
                requestCode(.confirmSignUp, channel: .email)
            }
        case .wrongCredentials where auth.emailCodesAvailable && !isSignUp,
             .wrongPassword where auth.emailCodesAvailable:
            AuthSecondaryButton(title: "Reset password", symbol: "key.fill") { go(to: .forgotPassword) }
        case .noAccount where !isSignUp:
            AuthSecondaryButton(title: "Create an account", symbol: "person.badge.plus") { switchIntent() }
        case .emailInUse where isSignUp:
            AuthSecondaryButton(title: "Sign in instead", symbol: "arrow.right.circle") { switchIntent() }
        default:
            EmptyView()
        }
    }

    // MARK: - Forgot password

    private var forgotPasswordStep: some View {
        VStack(spacing: 12) {
            AuthHeader(title: "Forgot password", subtitle: String(localized: "We'll email you a reset code."))

            emailRow(submit: { requestCode(.resetPassword, channel: .email) })
                .duovaGlassCard()

            AuthMessages(notice: notice, error: errorMessage)
            followUp

            AuthPrimaryButton(title: "Send reset code", isWorking: auth.isWorking) {
                requestCode(.resetPassword, channel: .email)
            }
            .disabled(!emailIsValid || auth.isWorking)

            AuthLinkRow {
                Button("Back to sign in") { go(to: .main) }
            } trailing: {
                EmptyView()
            }
        }
    }

    // MARK: - Sign in with a code

    private var codeSignInStep: some View {
        VStack(spacing: 12) {
            AuthHeader(title: "Sign in with a code", subtitle: String(localized: "No password needed."))

            HStack(spacing: 10) {
                AuthChoiceChip(title: "Email", symbol: "envelope.fill", isSelected: codeChannel == .email) {
                    codeChannel = .email
                    focus = .email
                }
                AuthChoiceChip(
                    title: "Phone", symbol: "iphone", isSelected: codeChannel == .phone,
                    isEnabled: AuthFeatures.phoneCodes
                ) {
                    codeChannel = .phone
                    focus = .phone
                }
            }
            if !AuthFeatures.phoneCodes {
                Text("Text codes are coming soon.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            Group {
                if codeChannel == .phone {
                    AuthFieldRow(symbol: "phone.fill", onTap: { focus = .phone }) {
                        TextField("+1 555 010 0000", text: $phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .focused($focus, equals: .phone)
                    }
                } else {
                    emailRow(submit: { requestCode(.signIn, channel: .email) })
                }
            }
            .duovaGlassCard()

            AuthMessages(notice: notice, error: errorMessage)
            followUp

            AuthPrimaryButton(title: "Send code", isWorking: auth.isWorking) {
                requestCode(.signIn, channel: codeChannel)
            }
            .disabled((codeChannel == .phone ? !phoneIsValid : !emailIsValid) || auth.isWorking)

            AuthLinkRow {
                Button("Back to sign in") { go(to: .main) }
            } trailing: {
                EmptyView()
            }
        }
    }

    // MARK: - Enter code

    private func codeTitle(_ purpose: EmailCodePurpose) -> LocalizedStringKey {
        switch purpose {
        case .confirmSignUp: "Confirm your email"
        case .signIn: "Enter your code"
        case .passkeySignUp: "Create your passkey"
        case .resetPassword: "Set a new password"
        }
    }

    private func codeAction(_ purpose: EmailCodePurpose) -> LocalizedStringKey {
        switch purpose {
        case .confirmSignUp: "Confirm"
        case .signIn: "Sign in"
        case .passkeySignUp: "Verify & create passkey"
        case .resetPassword: "Save password & sign in"
        }
    }

    private var codeIsComplete: Bool { (6...10).contains(code.count) }

    private func canVerify(_ purpose: EmailCodePurpose) -> Bool {
        guard codeIsComplete, !auth.isWorking else { return false }
        return purpose != .resetPassword || PasswordRules.isSatisfied(newPassword, confirmation: confirmPassword)
    }

    private func enterCodeStep(_ purpose: EmailCodePurpose, _ channel: CodeChannel) -> some View {
        let destination = channel == .phone ? PhoneNormalizer.normalize(phone) : normalizedEmail
        return VStack(spacing: 12) {
            AuthHeader(title: codeTitle(purpose), subtitle: String(localized: "Code sent to \(destination)."))

            VStack(spacing: 0) {
                AuthFieldRow(symbol: "number", onTap: { focus = .code }) {
                    TextField("Code", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.body.monospacedDigit())
                        .focused($focus, equals: .code)
                        .onChange(of: code) { _, value in
                            let digits = String(value.filter(\.isNumber).prefix(10))
                            if digits != value { code = digits }
                            clearError()
                        }
                }
                if purpose == .resetPassword {
                    AuthFieldDivider()
                    AuthFieldRow(symbol: "lock.rotation", onTap: { focus = .newPassword }) {
                        PasswordInput(
                            placeholder: "New password", text: $newPassword, isRevealed: $showPassword, isNew: true)
                            .submitLabel(.next)
                            .focused($focus, equals: .newPassword)
                            .onSubmit { focus = .confirmPassword }
                        RevealPasswordButton(isRevealed: $showPassword)
                    }
                    AuthFieldDivider()
                    AuthFieldRow(symbol: "checkmark.shield.fill", onTap: { focus = .confirmPassword }) {
                        PasswordInput(
                            placeholder: "Confirm new password", text: $confirmPassword,
                            isRevealed: $showPassword, isNew: true)
                            .submitLabel(.go)
                            .focused($focus, equals: .confirmPassword)
                            .onSubmit { verify(purpose, channel) }
                    }
                }
            }
            .duovaGlassCard()

            if purpose == .resetPassword {
                PasswordRules(password: newPassword, confirmation: confirmPassword)
            }
            if purpose == .passkeySignUp {
                FormMessage(text: String(localized: "Next, save a passkey."), kind: .info)
                    .padding(.horizontal, 4)
            }
            if purpose == .confirmSignUp {
                FormMessage(text: String(localized: "Or tap the link in the email."), kind: .info)
                    .padding(.horizontal, 4)
            }

            AuthMessages(notice: notice, error: errorMessage)

            AuthPrimaryButton(title: codeAction(purpose), isWorking: auth.isWorking) { verify(purpose, channel) }
                .disabled(!canVerify(purpose))

            AuthLinkRow {
                Button("Back") { leaveCodeStep(purpose) }
            } trailing: {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let wait = max(0, Int(resendAvailableAt.timeIntervalSince(context.date).rounded(.up)))
                    Button(wait > 0 ? "Resend in \(wait)s" : "Resend code") { resend(purpose, channel) }
                        .monospacedDigit()
                        .disabled(wait > 0 || auth.isWorking)
                }
            }
        }
    }

    // MARK: - Shared rows

    private func emailRow(submit: @escaping () -> Void) -> some View {
        AuthFieldRow(symbol: "envelope.fill", onTap: { focus = .email }) {
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focus, equals: .email)
                .onSubmit(submit)
        }
    }

    // MARK: - Navigation

    private func go(to next: Screen) {
        focus = nil
        clearError()
        notice = nil
        code = ""
        newPassword = ""
        confirmPassword = ""
        withAnimation(.easeInOut(duration: 0.2)) { screen = next }
        switch next {
        case .forgotPassword where !emailIsValid, .codeSignIn where !emailIsValid: focus = .email
        case .enterCode: focus = .code
        default: break
        }
    }

    private func switchIntent() {
        withAnimation(.easeInOut(duration: 0.2)) {
            intent = isSignUp ? .signIn : .signUp
        }
        clearError()
        notice = nil
    }

    private func leaveCodeStep(_ purpose: EmailCodePurpose) {
        switch purpose {
        case .resetPassword: go(to: .forgotPassword)
        case .signIn: go(to: .codeSignIn)
        case .confirmSignUp, .passkeySignUp: go(to: .main)
        }
        pendingPassword = nil
    }

    // MARK: - Actions

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        clearError()
        notice = nil
        let remember = rememberWithBiometrics
        let chosen = password
        Task {
            do {
                let outcome = try await auth.submit(
                    email: email, password: chosen, intent: intent,
                    acceptedTerms: acceptedTerms, rememberWithBiometrics: remember)
                password = ""
                if outcome == .confirmationSent {
                    pendingPassword = chosen
                    intent = .signIn
                    showCodeStep(.confirmSignUp, channel: .email)
                }
            } catch {
                report(error)
            }
        }
    }

    /// Asks the server to send a code, then opens the code step.
    private func requestCode(_ purpose: EmailCodePurpose, channel: CodeChannel) {
        focus = nil
        clearError()
        notice = nil
        Task {
            do {
                if channel == .phone {
                    try await auth.requestPhoneCode(phone: phone)
                } else {
                    try await auth.requestEmailCode(email: email, purpose: purpose, acceptedTerms: acceptedTerms)
                }
                showCodeStep(purpose, channel: channel)
            } catch {
                report(error)
            }
        }
    }

    private func showCodeStep(_ purpose: EmailCodePurpose, channel: CodeChannel) {
        go(to: .enterCode(purpose, channel))
        resendAvailableAt = .now.addingTimeInterval(30)
        let message = channel == .phone
            ? String(localized: "Code sent. Check your texts.")
            : String(localized: "Code sent. Check your email.")
        notice = message
        AccessibilityNotification.Announcement(message).post()
    }

    private func resend(_ purpose: EmailCodePurpose, _ channel: CodeChannel) {
        clearError()
        Task {
            do {
                if channel == .phone {
                    try await auth.requestPhoneCode(phone: phone)
                } else {
                    try await auth.requestEmailCode(email: email, purpose: purpose, acceptedTerms: acceptedTerms)
                }
                resendAvailableAt = .now.addingTimeInterval(30)
                notice = String(localized: "New code sent.")
            } catch {
                report(error)
            }
        }
    }

    private func verify(_ purpose: EmailCodePurpose, _ channel: CodeChannel) {
        guard canVerify(purpose) else { return }
        focus = nil
        clearError()
        notice = nil
        let entered = code
        let chosen = purpose == .resetPassword ? newPassword : pendingPassword
        let remember = rememberWithBiometrics
        Task {
            do {
                if channel == .phone {
                    try await auth.verifyPhoneCode(phone: phone, code: entered)
                } else {
                    _ = try await auth.verifyEmailCode(
                        email: email, code: entered, purpose: purpose,
                        password: chosen, rememberWithBiometrics: remember)
                }
                code = ""
                newPassword = ""
                confirmPassword = ""
                pendingPassword = nil
            } catch {
                code = ""
                report(error)
                focus = .code
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        clearError()
        notice = nil
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                present(String(localized: "Apple sign-in didn't finish."))
                return
            }
            let nonce = appleNonce
            Task {
                do {
                    try await auth.signInWithApple(
                        userID: credential.user, email: credential.email, fullName: credential.fullName,
                        identityToken: credential.identityToken, rawNonce: nonce)
                } catch {
                    report(error)
                }
            }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            present(String(localized: "Apple sign-in unavailable now."))
        }
    }

    private func usePasskey() {
        clearError()
        if isSignUp {
            guard emailIsValid else {
                present(String(localized: "Enter your email first."))
                focus = .email
                return
            }
            if auth.usesCloud {
                // Prove the email with a code first; the passkey is created right after.
                requestCode(.passkeySignUp, channel: .email)
            } else {
                focus = nil
                Task {
                    do { try await auth.signUpWithPasskey(email: email, acceptedTerms: acceptedTerms) } catch {
                        report(error)
                    }
                }
            }
        } else {
            signInWithPasskey()
        }
    }

    private func signInWithPasskey() {
        focus = nil
        clearError()
        Task {
            do { try await auth.signInWithPasskey() } catch { report(error) }
        }
    }

    private func signInWithBiometrics() {
        focus = nil
        clearError()
        Task {
            switch await auth.signInWithBiometrics() {
            case .success, .cancelled:
                break
            case .unavailable:
                present(String(localized: "\(kind.title) not set up."))
            case .failed(let reason):
                present(reason)
            }
        }
    }

    // MARK: - Messages

    private func clearError() {
        errorMessage = nil
        lastError = nil
    }

    private func report(_ error: Error) {
        if error is CancellationError { return }
        if let error = error as? AuthError {
            lastError = error
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
        .environment(AuthController(store: SecureStore(directory: URL.temporaryDirectory.appending(path: "duova-preview"), keyService: "com.duova.preview"), usesCloud: false))
        .duovaTheme()
}
