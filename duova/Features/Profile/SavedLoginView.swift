import SwiftUI

/// The login Duova keeps for one app. Opening it asks for Face ID / Touch ID /
/// passcode first; everything saved is double-encrypted on this device before
/// it's stored or synced. One-time codes are never saved.
///
/// A saved login is shown first, with Edit and Delete. Save only turns on once
/// something changed, and closing the card with unsaved changes asks first.
struct SavedLoginView: View {
    @Environment(\.duovaTheme) private var theme
    @Environment(AuthController.self) private var auth
    @Environment(AppSignInCenter.self) private var signIn
    @Environment(DeviceKeyring.self) private var keyring

    let service: Service

    @State private var unlocked = false
    @State private var login = AppLogin()
    /// What's stored now; nil when nothing is saved.
    @State private var saved: AppLogin?
    @State private var editing = false
    @State private var showPassword = false
    @State private var message: String?
    @State private var notice: String?
    @State private var isSaving = false
    @State private var confirmRemove = false

    private var store: AppLoginStore? {
        auth.account.flatMap { try? AppLoginStore(accountID: $0.id) }
    }

    private var hasChanges: Bool { editing && login != (saved ?? AppLogin()) }

    private var canSave: Bool {
        guard hasChanges, !isSaving else { return false }
        if login.method.usesPassword {
            return !login.identifier.trimmingCharacters(in: .whitespaces).isEmpty && !login.password.isEmpty
        }
        return true
    }

    /// The site whose saved password to pick from the keyboard's Passwords list.
    private var website: String? {
        signIn.recipe(for: service.id)?.hosts.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Saved Login")
                    .font(.title2.bold())
                    .foregroundStyle(theme.textPrimary)
                    .padding(.top, 8)
                    .padding(.trailing, 44)
                    .accessibilityAddTraits(.isHeader)
                if !unlocked {
                    locked
                } else if editing {
                    form
                } else if let saved {
                    summary(saved)
                }
            }
            .padding(.horizontal, DuovaMetrics.screenMargin)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background { DuovaBackdrop() }
        .pageSheetCloseDisabled(isSaving)
        .cardDiscardGuard(hasChanges)
        .cardCloseButton()
        .task { await unlock() }
        .confirmationDialog("Delete saved login?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { remove() }
        } message: {
            Text("Duova forgets this login for \(service.name).")
        }
    }

    private var locked: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(theme.textSecondary)
            Text("Saved logins are locked.")
                .foregroundStyle(theme.textPrimary)
            if let message {
                FormMessage(text: message, kind: .error)
            }
            ProminentActionButton(title: "Unlock", isWorking: false) {
                Task { await unlock() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: Saved

    @ViewBuilder
    private func summary(_ saved: AppLogin) -> some View {
        SettingsGroup(title: "\(service.name) login", footer: "Encrypted twice on this device before it's stored.") {
            SettingsValueRow(title: "Method", value: saved.method.title)
            if !saved.identifier.isEmpty {
                SettingsValueRow(title: LocalizedStringKey(saved.method.identifierTitle), value: saved.identifier)
            }
            if saved.method.usesPassword {
                SettingsValueRow(title: "Password", value: "••••••••")
            }
            SettingsValueRow(title: "Code arrives by", value: saved.codeDelivery.title)
        }

        if let notice { FormMessage(text: notice, kind: .success) }
        if let message { FormMessage(text: message, kind: .error) }

        ProminentActionButton(title: "Edit Login", isWorking: false) {
            login = saved
            notice = nil
            message = nil
            editing = true
        }

        SettingsGroup {
            SettingsButtonRow(symbol: "trash.fill", title: "Delete Saved Login", isDestructive: true) {
                confirmRemove = true
            }
        }
    }

    // MARK: Editing

    @ViewBuilder
    private var form: some View {
        SettingsGroup(title: "How you sign in to \(service.name)") {
            SettingsMenuRow(symbol: "person.badge.key.fill", title: "Method", selection: $login.method)
        }

        SettingsGroup(title: login.method.usesPassword ? "Login" : "Account", footer: fieldsFooter) {
            FormFieldRow(symbol: login.method == .usernamePassword ? "person.fill" : "envelope.fill") {
                TextField(login.method.identifierTitle, text: $login.identifier)
                    .keyboardType(login.method == .usernamePassword ? .default : .emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(maxWidth: .infinity)
            }
            if login.method.usesPassword {
                FormFieldRow(symbol: "lock.fill") {
                    Group {
                        if showPassword {
                            TextField("Password", text: $login.password)
                        } else {
                            SecureField("Password", text: $login.password)
                        }
                    }
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(maxWidth: .infinity)
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                }
            }
        }

        SettingsGroup(
            title: "Verification code",
            footer: "Codes are never saved. Duova tells you to expect one."
        ) {
            SettingsMenuRow(symbol: "number", title: "Code arrives by", selection: $login.codeDelivery)
        }

        if let notice { FormMessage(text: notice, kind: .success) }
        if let message { FormMessage(text: message, kind: .error) }

        ProminentActionButton(title: "Save Login", isWorking: isSaving, action: save)
            .disabled(!canSave)

        if saved != nil {
            Button("Cancel Editing") {
                login = saved ?? AppLogin()
                showPassword = false
                editing = false
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(theme.accent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .disabled(isSaving)
        }
    }

    private var fieldsFooter: LocalizedStringKey {
        guard login.method.usesPassword else { return "No password is kept for this method." }
        if let website {
            return "Tap the key on the keyboard and search \(website) to use a password you saved. Encrypted twice before it's stored."
        }
        return "Encrypted twice on this device before it's stored."
    }

    // MARK: Actions

    private func unlock() async {
        guard !unlocked else { return }
        message = nil
        switch await BiometricAuthenticator.authenticate(
            reason: String(localized: "Unlock saved logins for \(service.name).")) {
        case .success:
            guard let store else {
                if case .waitingForApproval = keyring.state {
                    message = String(localized: "Approve this device first.")
                } else {
                    message = String(localized: "Account unavailable. Sign in again.")
                }
                return
            }
            var found = store.login(for: service.id.rawValue)
            if found == nil { found = await store.restoreFromCloud(for: service.id.rawValue) }
            saved = found
            login = found ?? AppLogin()
            editing = found == nil
            unlocked = true
        case .cancelled:
            break
        case .unavailable:
            message = String(localized: "Set a device passcode first.")
        case .failed(let reason):
            message = reason
        }
    }

    private func save() {
        guard canSave, let store else { return }
        isSaving = true
        message = nil
        notice = nil
        var value = login
        value.identifier = value.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.method.usesPassword { value.password = "" }
        Task {
            defer { isSaving = false }
            do {
                let synced = try await store.save(value, for: service.id.rawValue)
                signIn.loginChanged(service.id)
                saved = value
                login = value
                showPassword = false
                editing = false
                notice = synced
                    ? String(localized: "Saved and synced.")
                    : String(localized: "Saved on this device.")
            } catch {
                message = String(localized: "Couldn't save. Unlock device.")
            }
        }
    }

    private func remove() {
        guard let store else { return }
        Task {
            await store.remove(for: service.id.rawValue)
            signIn.loginChanged(service.id)
            saved = nil
            login = AppLogin()
            editing = true
            notice = String(localized: "Login deleted.")
        }
    }
}
