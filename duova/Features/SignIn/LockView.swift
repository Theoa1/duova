import SwiftUI

/// Unlock screen for a returning, signed-in user with App Lock on.
///
/// Two ways in, so nobody is stuck outside their own app: Touch ID / Face ID
/// (whose system prompt falls back to the device passcode by itself), and the
/// Duova account password.
///
/// The identity (picture, name) is one half of the screen and the
/// controls the other: stacked in portrait, side by side in landscape, and one
/// per page when the device is open. The picture scales with the space it gets.
struct LockView: View {
    @Environment(\.duovaTheme) private var theme
    @Environment(\.bookPosture) private var book
    @Environment(AuthController.self) private var auth
    @Environment(\.scenePhase) private var scenePhase

    @State private var usePassword = false
    @State private var password = ""
    @State private var message: String?
    @State private var isPrompting = false
    @State private var hasAutoPrompted = false
    @State private var confirmSignOut = false
    @State private var confirmReset = false
    @State private var windowSize: CGSize = .zero
    @FocusState private var passwordFocused: Bool

    private var kind: BiometricKind { auth.biometricKind }

    /// The password box is shown on request, or straight away when the device
    /// offers nothing else.
    private var showsPassword: Bool {
        usePassword || (!kind.isAvailable && auth.accountHasPassword)
    }

    var body: some View {
        AuthScaffold {
            identity
        } panel: { proxy in
            controls
                .id("lockPanel")
                .revealOnFocus($passwordFocused, in: proxy, id: "lockPanel")
        }
        .background {
            Color.clear
                .ignoresSafeArea()
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { windowSize = $0 }
        }
        .task(id: scenePhase) {
            // Prompt once per lock, and only once the app is really in front:
            // a prompt shown while the app is still starting is cancelled by the
            // system. Cancelling leaves the buttons available and shows no error.
            guard kind.isAvailable, scenePhase == .active, !hasAutoPrompted else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, scenePhase == .active else { return }
            hasAutoPrompted = true
            await unlock(automatic: true)
        }
        .confirmationDialog("Sign out of Duova?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { auth.signOut() }
        } message: {
            Text("You'll need your email and password to sign in again. Your settings and favorites stay saved, encrypted, on this device.")
        }
        .confirmationDialog("Reset your password?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Sign Out & Reset") { auth.signOutToResetPassword() }
        } message: {
            Text("You'll be signed out, then we'll email a code to \(auth.account?.email ?? "").")
        }
    }

    // MARK: Identity

    /// Size of the profile picture, from the space one half of the screen gets.
    private var pictureSize: CGFloat {
        let w = windowSize.width
        let h = windowSize.height
        guard w > 0, h > 0 else { return 104 }
        let page: CGFloat
        if let book {
            page = book.axis == .horizontal ? min(w / 2, h) : min(w, h / 2)
        } else if w > h * 1.1 {
            page = min(w / 2, h)
        } else {
            page = min(w, h * 0.55)
        }
        return min(176, max(88, page * 0.3))
    }

    private var identity: some View {
        VStack(spacing: 22) {
            if let account = auth.account {
                VStack(spacing: 14) {
                    AvatarView(initials: account.initials, image: auth.avatar, size: pictureSize)
                        .shadow(color: theme.accent.opacity(0.25), radius: 18, y: 8)

                    VStack(spacing: 4) {
                        Text(account.name)
                            .font(pictureSize > 130 ? .largeTitle.bold() : .title.bold())
                            .foregroundStyle(theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        Text(account.displayEmail)
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Label("Locked", systemImage: "lock.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .glassEffect(.regular, in: Capsule())
                        .padding(.top, 2)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 12) {
            if showsPassword {
                passwordEntry
            } else {
                unlockButtons
            }

            if let message {
                FormMessage(text: message, kind: .error)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("Sign out", role: .destructive) {
                confirmSignOut = true
            }
            .font(.subheadline)
            .frame(minHeight: 44)
        }
    }

    @ViewBuilder
    private var unlockButtons: some View {
        if kind.isAvailable {
            Button {
                Task { await unlock() }
            } label: {
                Label(
                    kind.isBiometric ? "Unlock with \(kind.title)" : "Unlock with Device Passcode",
                    systemImage: kind.systemImage
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: DuovaMetrics.cornerRadius))
            .controlSize(.extraLarge)
            .tint(theme.accent)
            .foregroundStyle(theme.onAccent)
            .disabled(isPrompting)
        } else {
            FormMessage(
                text: String(localized: "Set a device passcode first."),
                kind: .error
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if auth.accountHasPassword {
            fallbackButton("Use account password", symbol: "key.fill") {
                message = nil
                usePassword = true
                passwordFocused = true
            }
        }
    }

    private func fallbackButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: DuovaMetrics.cornerRadius))
        .controlSize(.large)
        .foregroundStyle(theme.textPrimary)
    }

    private var passwordEntry: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                SecureField("Account password", text: $password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($passwordFocused)
                    .onSubmit { Task { await unlockWithPassword() } }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
            .onTapGesture { passwordFocused = true }
            .duovaGlassCard()

            Button {
                Task { await unlockWithPassword() }
            } label: {
                Group {
                    if auth.isWorking { ProgressView().tint(theme.onAccent) } else { Text("Unlock").font(.headline) }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: DuovaMetrics.cornerRadius))
            .controlSize(.extraLarge)
            .tint(theme.accent)
            .foregroundStyle(theme.onAccent)
            .disabled(password.isEmpty || auth.isWorking)

            if auth.usesCloud, auth.account?.email.isEmpty == false {
                Button("Forgot password?") {
                    passwordFocused = false
                    confirmReset = true
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.accent)
                .frame(minHeight: 44)
            }

            if kind.isAvailable {
                Button(kind.isBiometric ? "Use \(kind.title)" : "Use device passcode") {
                    usePassword = false
                    password = ""
                    message = nil
                    passwordFocused = false
                }
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .frame(minHeight: 44)
            }
        }
    }

    // MARK: Actions

    private func unlock(automatic: Bool = false) async {
        guard !isPrompting else { return }
        isPrompting = true
        defer { isPrompting = false }
        switch await auth.unlockWithBiometrics() {
        case .success, .cancelled:
            message = nil
        case .unavailable:
            if auth.accountHasPassword { usePassword = true }
            message = auth.accountHasPassword
                ? String(localized: "\(kind.title) unavailable. Use password.")
                : String(localized: "\(kind.title) unavailable. Set passcode.")
        case .failed(let reason):
            // An automatic prompt that was interrupted stays quiet; the buttons are right there.
            message = automatic ? nil : reason
        }
    }

    private func unlockWithPassword() async {
        guard !password.isEmpty else { return }
        do {
            try await auth.unlockWithPassword(password)
            password = ""
        } catch let error as AuthError {
            message = error.errorDescription
        } catch {
            message = String(localized: "Something went wrong. Try again.")
        }
    }
}
