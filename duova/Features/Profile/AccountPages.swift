import SwiftUI

// MARK: - Personal information

struct PersonalInformationPage: View {
    @Environment(AuthController.self) private var auth
    @State private var showEdit = false
    @State private var showDelete = false

    var body: some View {
        SettingsPage(title: "Personal Information") {
            if let account = auth.account {
                SettingsGroup(title: "Profile") {
                    SettingsValueRow(title: "Name", value: account.name)
                    SettingsValueRow(title: "Email", value: account.displayEmail)
                    SettingsValueRow(
                        title: "Member since",
                        value: account.createdAt.formatted(date: .abbreviated, time: .omitted))
                }
            }

            SettingsGroup(footer: "A profile photo is optional. Without one, Duova shows your initials.") {
                SettingsButtonRow(symbol: "pencil", title: "Edit Profile") { showEdit = true }
            }

            SettingsGroup(
                title: "Delete",
                footer: "Deleting your account erases your profile, favorites, preferences and sign-in details from this device. It doesn't affect your accounts on other services."
            ) {
                SettingsButtonRow(symbol: "trash.fill", title: "Delete Account…", isDestructive: true) {
                    showDelete = true
                }
            }
        }
        .pageSheet(isPresented: $showEdit) { EditProfileView() }
        .pageSheet(isPresented: $showDelete) { DeleteAccountView() }
    }
}

// MARK: - Sign-in & App Lock

struct SignInSecurityPage: View {
    @Environment(AuthController.self) private var auth
    @State private var showChangePassword = false
    @State private var message: String?
    @State private var isUpdating = false

    private var kind: BiometricKind { auth.biometricKind }

    var body: some View {
        SettingsPage(title: "Sign-In & \(kind.title)") {
            SettingsGroup(
                title: "Account sign-in",
                footer: auth.accountHasPassword
                    ? "Your password is never stored, only a salted one-way hash protected by the Keychain."
                    : "This account has no password. Duova never sees your Apple ID password or passkey."
            ) {
                if let account = auth.account {
                    SettingsValueRow(title: "Email", value: account.displayEmail)
                }
                if auth.accountHasPassword {
                    SettingsButtonRow(symbol: "key.fill", title: "Change Password") {
                        showChangePassword = true
                    }
                } else {
                    SettingsValueRow(
                        title: "Signs in with",
                        value: auth.account?.appleUserID != nil ? String(localized: "Apple") : String(localized: "Passkey"))
                }
            }

            SettingsGroup(
                title: "App Lock",
                footer: kind.isAvailable
                    ? "\(kind.title) only unlocks Duova on this device. It doesn't replace your account password, which you still need to sign in. Never means Duova won't lock again while it stays open in the background; opening it fresh still asks."
                    : "Set up Touch ID, Face ID or a device passcode in Settings to use App Lock."
            ) {
                SettingsToggleRow(
                    symbol: kind.systemImage,
                    title: "Unlock with \(kind.title)",
                    subtitle: "Ask each time you return to Duova",
                    isOn: Binding(
                        get: { auth.settings.appLockEnabled },
                        set: { setAppLock($0) }
                    )
                )
                .disabled(!kind.isAvailable || isUpdating)

                if auth.settings.appLockEnabled {
                    SettingsMenuRow(
                        symbol: "timer", title: "Require \(kind.title)",
                        selection: Binding(
                            get: { auth.settings.lockTimeout },
                            set: { auth.setLockTimeout($0) }
                        )
                    )
                }
            }

            if kind.isBiometric {
                SettingsGroup(
                    title: "Sign in with \(kind.title)",
                    footer: auth.biometricSignInReady
                        ? "Your sign-in is saved behind \(kind.title) on this device. Turn it off to remove it."
                        : "To turn this on, sign out, then switch on \"Use \(kind.title) next time\" when you sign in."
                ) {
                    SettingsToggleRow(
                        symbol: kind.systemImage,
                        title: "Sign in with \(kind.title)",
                        subtitle: "Skip typing your password",
                        isOn: Binding(
                            get: { auth.biometricSignInReady },
                            set: { if !$0 { auth.disableBiometricSignIn() } }
                        )
                    )
                    .disabled(!auth.biometricSignInReady)
                }
            }

            if let message {
                FormMessage(text: message, kind: .error)
            }
        }
        .pageSheet(isPresented: $showChangePassword) { ChangePasswordView() }
    }

    private func setAppLock(_ enabled: Bool) {
        isUpdating = true
        message = nil
        Task {
            defer { isUpdating = false }
            switch await auth.setAppLock(enabled: enabled) {
            case .success, .cancelled:
                break
            case .unavailable:
                message = String(localized: "\(kind.title) isn't available. Set it up in Settings first.")
            case .failed(let reason):
                message = reason
            }
        }
    }
}

// MARK: - Devices & sessions

extension LockTimeout: MenuOption {}

struct SessionsPage: View {
    @Environment(AuthController.self) private var auth
    @State private var confirmSignOut = false

    var body: some View {
        SettingsPage(title: "Devices & Sessions") {
            SettingsGroup(title: "This device") {
                SettingsValueRow(title: "Device", value: UIDevice.current.model)
                SettingsValueRow(title: "System", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
                if let started = auth.sessionStartedAt {
                    SettingsValueRow(
                        title: "Signed in",
                        value: started.formatted(date: .abbreviated, time: .shortened))
                }
                SettingsValueRow(
                    title: "App Lock",
                    value: auth.settings.appLockEnabled ? String(localized: "On") : String(localized: "Off"))
            }

            SettingsGroup(
                title: "Other devices",
                footer: "Your Duova account is stored encrypted on this device only, so there are no other active sessions to review or revoke."
            ) {
                SettingsValueRow(title: "Active sessions", value: String(localized: "None"))
            }

            SettingsGroup(footer: "You'll need your email and password to sign in again.") {
                SettingsButtonRow(symbol: "rectangle.portrait.and.arrow.right",
                                  title: "Sign Out of This Device", isDestructive: true) {
                    confirmSignOut = true
                }
            }
        }
        .confirmationDialog("Sign out of Duova?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { auth.signOut() }
        } message: {
            Text("You'll need your email and password to sign in again. Your settings and favorites stay saved, encrypted, on this device.")
        }
    }
}

// MARK: - Storage & cache

nonisolated enum StorageUsage {
    @concurrent
    static func bytes(in directory: URL) async -> Int64 {
        measure(directory)
    }

    private static func measure(_ directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: keys, options: [], errorHandler: nil)
        else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true {
                total += Int64(values?.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }

    /// Removes disposable cached files only. Account data, preferences and
    /// sign-in state are stored elsewhere and are not touched.
    @concurrent
    static func clearCaches() async {
        let fileManager = FileManager.default
        let items = (try? fileManager.contentsOfDirectory(at: .cachesDirectory, includingPropertiesForKeys: nil)) ?? []
        for item in items { try? fileManager.removeItem(at: item) }
        URLCache.shared.removeAllCachedResponses()
    }
}

struct StoragePage: View {
    @State private var cacheBytes: Int64?
    @State private var dataBytes: Int64?
    @State private var confirmClear = false
    @State private var isClearing = false

    var body: some View {
        SettingsPage(title: "Storage & Cache") {
            SettingsGroup(title: "On this device") {
                SettingsValueRow(title: "Temporary cache", value: format(cacheBytes))
                SettingsValueRow(title: "Account data", value: format(dataBytes))
            }

            SettingsGroup(
                footer: "Clearing the temporary cache frees space. It doesn't sign you out or remove your account, preferences or favorites."
            ) {
                SettingsButtonRow(symbol: "trash", title: "Clear Temporary Cache") {
                    confirmClear = true
                }
                .disabled(isClearing)
            }
        }
        .task { await refresh() }
        .confirmationDialog("Clear temporary cache?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear Cache", role: .destructive) {
                Task {
                    isClearing = true
                    await StorageUsage.clearCaches()
                    await refresh()
                    isClearing = false
                }
            }
        } message: {
            Text("Only disposable files are removed.")
        }
    }

    private func refresh() async {
        cacheBytes = await StorageUsage.bytes(in: .cachesDirectory)
        dataBytes = await StorageUsage.bytes(in: .applicationSupportDirectory)
    }

    private func format(_ bytes: Int64?) -> String {
        guard let bytes else { return "…" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - About

struct AboutPage: View {
    @Environment(\.duovaTheme) private var theme

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        SettingsPage(title: "About Duova") {
            VStack(spacing: 12) {
                DuovaMark(style: theme.markStyle)
                    .frame(width: 88, height: 88)
                Text("Duova")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                Text("Your apps. Reimagined.")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)

            SettingsGroup(title: "Version") {
                SettingsValueRow(title: "Version", value: version)
                SettingsValueRow(title: "Build", value: build)
            }

            SettingsGroup(title: "Your data") {
                infoRow(symbol: "lock.shield.fill",
                        text: "Your email, name, photo, favorites and preferences are encrypted on this device with AES-256, using a key held in the iOS Keychain.")
                infoRow(symbol: "key.fill",
                        text: "Your password is never stored. Only a salted one-way hash is kept, and that hash is encrypted too.")
                infoRow(symbol: "person.2.slash.fill",
                        text: "Your Duova account is separate from your accounts on other services. Signing in to Duova doesn't sign you in to them.")
            }
        }
    }

    private func infoRow(symbol: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsIcon(symbol: symbol)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
