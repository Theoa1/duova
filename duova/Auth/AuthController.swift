import AuthenticationServices
import Foundation
import Observation
import UIKit
import WebKit

/// Owns the Duova account session.
///
/// Sign-in and sign-up are one flow: `submit` signs an existing account in or
/// creates a new one. The session persists (encrypted) until the user signs
/// out, so signing in ordinarily happens once. App Lock, when enabled, only
/// asks for Touch ID / Face ID / passcode, never the password.
///
/// All account data goes through `SecureStore` (AES-256-GCM, Keychain-held
/// key). Passwords are stored only as salted PBKDF2 hashes.
@Observable
final class AuthController {
    enum Phase: Equatable {
        case signedOut
        /// Signed in, but App Lock requires a biometric or passcode check.
        case locked
        case active
    }

    private enum Name {
        static let accounts = "accounts"
        static let session = "session"
        static let links = "identity-links"
        static let biometricWanted = "biometric-signin-wanted"
        /// 2: the saved Face ID / Touch ID sign-in holds a set-aside session, never a password.
        static let biometricFormat = "biometric-signin-format"
        static func settings(_ id: UUID) -> String { "settings-\(id.uuidString)" }
        static func avatar(_ id: UUID) -> String { "avatar-\(id.uuidString)" }
    }

    private static let maxFailedAttempts = 5
    private static let lockoutSeconds: TimeInterval = 30

    private(set) var phase: Phase = .signedOut
    private(set) var account: DuovaAccount?
    private(set) var settings = AccountSettings()
    private(set) var sessionStartedAt: Date?
    private(set) var avatar: UIImage?
    /// True while a password is being hashed. Used to disable duplicate submissions.
    private(set) var isWorking = false
    private(set) var lockedOutUntil: Date?
    /// A Touch ID / Face ID sign-in has been saved on this device.
    private(set) var biometricSignInReady = false
    /// The signed-in account has a password (accounts made with Apple or a
    /// passkey may not).
    private(set) var accountHasPassword = false

    @ObservationIgnored private let store: SecureStore
    @ObservationIgnored private let vault: CredentialVault
    @ObservationIgnored private var failedAttempts = 0
    @ObservationIgnored private var backgroundedAt: Date?
    @ObservationIgnored private let passkeys = PasskeyAuthenticator()
    /// Duova's account service (Supabase Auth). nil when the backend isn't
    /// configured; then nobody can sign in unless this is a preview or test.
    @ObservationIgnored private let cloud: CloudAuthService?
    /// Accounts kept on this device only. Previews and tests ask for it
    /// explicitly; a build without its server never falls back to it.
    @ObservationIgnored private let localOnly: Bool
    /// The last sign-out still ending its server session. Every new sign-in
    /// waits for it, so an old sign-out can't land on the new session.
    @ObservationIgnored private var pendingSignOut: Task<Void, Never>?

    /// What the server currently allows. Buttons for sign-in methods the server
    /// hasn't turned on stay hidden.
    private(set) var capabilities = CloudCapabilities.none
    /// Passkeys registered to the signed-in account.
    private(set) var cloudPasskeys: [CloudPasskey] = []
    /// Set when the lock screen sends someone to reset their password; the
    /// sign-in screen opens "Forgot password" with this email.
    @ObservationIgnored private var requestedResetEmail: String?

    /// `usesCloud: false` keeps accounts on this device only (used by previews and tests).
    init(store: SecureStore = .shared, usesCloud: Bool = true) {
        self.store = store
        localOnly = !usesCloud
        cloud = usesCloud ? CloudAuthService() : nil
        vault = CredentialVault(store: store)
        restoreSession()
        removeOldBiometricSignIn()
        refreshBiometricSignIn()
    }

    // MARK: Queries

    func hasAccount(forEmail email: String) -> Bool {
        let normalized = EmailNormalizer.normalize(email)
        guard EmailNormalizer.isValid(normalized) else { return false }
        return vault.record(forEmail: normalized) != nil
    }

    var biometricKind: BiometricKind { BiometricAuthenticator.availability() }

    /// Accounts are held by Duova's servers (rather than only on this device).
    var usesCloud: Bool { cloud != nil }
    var appleSignInAvailable: Bool { cloud == nil ? localOnly : capabilities.apple }
    /// Passkeys come from the server when it's configured. Signing up with one
    /// first proves the email with a code, because the server only lets a
    /// signed-in account add a passkey.
    var passkeySignInAvailable: Bool { cloud == nil ? localOnly : capabilities.passkeys }
    var passkeySignUpAvailable: Bool { cloud == nil ? localOnly : capabilities.passkeys }
    /// Email codes (sign-in, confirmation, password reset) need the server.
    var emailCodesAvailable: Bool { cloud != nil }

    // MARK: Sign in / sign up

    /// Signs in to an existing account (`.signIn`) or creates one (`.signUp`).
    /// When `rememberWithBiometrics` is set and succeeds, the details are saved
    /// behind Touch ID / Face ID for next time.
    func submit(
        email: String, password: String, intent: AuthIntent,
        acceptedTerms: Bool = false, rememberWithBiometrics: Bool = false
    ) async throws -> SubmitOutcome {
        let normalized = EmailNormalizer.normalize(email)
        guard EmailNormalizer.isValid(normalized) else { throw AuthError.invalidEmail }
        try ensureNotLockedOut()
        let cloud = try accountService()
        guard !isWorking else { throw AuthError.busy }
        isWorking = true
        defer { isWorking = false }

        if let cloud {
            return try await submitToCloud(
                cloud, email: normalized, password: password, intent: intent,
                acceptedTerms: acceptedTerms, rememberWithBiometrics: rememberWithBiometrics)
        }

        let existing = vault.record(forEmail: normalized)
        let outcome: SubmitOutcome

        switch intent {
        case .signIn:
            guard let record = existing else {
                registerFailure()
                throw lockoutError() ?? AuthError.wrongCredentials
            }
            try await verify(password, against: record)
            guard let found = loadAccounts().first(where: { $0.id == record.accountID }) else {
                throw AuthError.accountUnavailable
            }
            beginSession(for: found)
            outcome = .signedIn

        case .signUp:
            guard existing == nil else { throw AuthError.emailInUse }
            guard acceptedTerms else { throw AuthError.termsNotAccepted }
            if let issue = PasswordPolicy.validate(password, email: normalized) {
                throw AuthError.weakPassword(issue)
            }
            let salt = PasswordHasher.randomSalt()
            let hash = await PasswordHasher.derive(password: password, salt: salt, iterations: PasswordHasher.iterations)
            let created = DuovaAccount(
                id: UUID(), email: normalized, name: Self.defaultName(from: normalized), createdAt: .now,
                termsAcceptedAt: .now)
            do {
                try vault.save(
                    CredentialRecord(accountID: created.id, salt: salt, hash: hash, iterations: PasswordHasher.iterations),
                    forEmail: normalized)
                try store.save(loadAccounts() + [created], name: Name.accounts)
            } catch {
                vault.remove(forEmail: normalized)
                throw AuthError.storageFailure
            }
            beginSession(for: created)
            outcome = .created
        }

        if rememberWithBiometrics { rememberBiometricSignIn() }
        return outcome
    }

    /// Email sign-in and sign-up against Supabase Auth. The password is
    /// checked by the server; a salted local verifier is refreshed from it so
    /// App Lock's "Use account password" still works offline.
    private func submitToCloud(
        _ cloud: CloudAuthService, email: String, password: String, intent: AuthIntent,
        acceptedTerms: Bool, rememberWithBiometrics: Bool
    ) async throws -> SubmitOutcome {
        await finishPendingSignOut()
        let outcome: SubmitOutcome
        switch intent {
        case .signIn:
            let user: CloudUser
            do {
                user = try await cloud.signIn(email: email, password: password)
            } catch AuthError.wrongCredentials {
                registerFailure()
                throw lockoutError() ?? AuthError.wrongCredentials
            }
            failedAttempts = 0
            let found = try await adopt(user, fallbackEmail: email, password: password)
            beginSession(for: found)
            outcome = .signedIn

        case .signUp:
            guard acceptedTerms else { throw AuthError.termsNotAccepted }
            if let issue = PasswordPolicy.validate(password, email: email) {
                throw AuthError.weakPassword(issue)
            }
            switch try await cloud.signUp(email: email, password: password) {
            case .confirmationRequired:
                return .confirmationSent
            case .signedIn(let user):
                let found = try await adopt(user, fallbackEmail: email, password: password)
                beginSession(for: found)
                outcome = .created
            }
        }
        if rememberWithBiometrics { rememberBiometricSignIn() }
        return outcome
    }

    // MARK: Email codes

    /// Emails a one-time code for `purpose`.
    func requestEmailCode(email: String, purpose: EmailCodePurpose, acceptedTerms: Bool = false) async throws {
        guard let cloud else { throw AuthError.methodNotEnabled }
        let normalized = EmailNormalizer.normalize(email)
        guard EmailNormalizer.isValid(normalized) else { throw AuthError.invalidEmail }
        guard !isWorking else { throw AuthError.busy }
        isWorking = true
        defer { isWorking = false }
        await finishPendingSignOut()

        switch purpose {
        case .confirmSignUp:
            try await cloud.resendSignUpCode(to: normalized)
        case .signIn:
            // Same answer whether or not the email has an account.
            do {
                try await cloud.sendSignInCode(to: normalized, createAccount: false)
            } catch AuthError.noAccount {}
        case .passkeySignUp:
            guard acceptedTerms else { throw AuthError.termsNotAccepted }
            guard capabilities.passkeys else { throw AuthError.methodNotEnabled }
            try await cloud.sendSignInCode(to: normalized, createAccount: true)
        case .resetPassword:
            try await cloud.sendPasswordReset(to: normalized)
        }
    }

    /// Checks an emailed code and finishes the flow it was sent for. The code
    /// isn't kept anywhere. `password` is the new password for a reset, or the
    /// one just chosen when confirming a sign-up.
    func verifyEmailCode(
        email: String, code: String, purpose: EmailCodePurpose,
        password: String? = nil, rememberWithBiometrics: Bool = false
    ) async throws -> CodeOutcome {
        guard let cloud else { throw AuthError.methodNotEnabled }
        let normalized = EmailNormalizer.normalize(email)
        let digits = code.filter(\.isNumber)
        guard (6...10).contains(digits.count) else { throw AuthError.codeInvalid }
        if purpose == .resetPassword {
            guard let password else { throw AuthError.weakPassword(.tooShort) }
            if let issue = PasswordPolicy.validate(password, email: normalized) { throw AuthError.weakPassword(issue) }
        }
        try ensureNotLockedOut()
        guard !isWorking else { throw AuthError.busy }
        isWorking = true
        defer { isWorking = false }
        await finishPendingSignOut()

        let kind: CloudAuthService.CodeKind = switch purpose {
        case .confirmSignUp: .signUp
        case .signIn, .passkeySignUp: .signIn
        case .resetPassword: .recovery
        }
        let user: CloudUser
        do {
            user = try await cloud.verify(code: digits, email: normalized, kind: kind)
        } catch AuthError.codeInvalid {
            registerFailure()
            throw lockoutError() ?? AuthError.codeInvalid
        }
        failedAttempts = 0

        var outcome = CodeOutcome.signedIn
        switch purpose {
        case .resetPassword:
            try await cloud.updatePassword(to: password ?? "")
            // A new password ends every other session, including one kept for Face ID / Touch ID.
            await cloud.signOutOtherSessions()
        case .passkeySignUp:
            do {
                try await cloud.registerPasskey()
                outcome = .passkeyAdded
            } catch {
                outcome = .passkeySkipped
            }
        case .confirmSignUp, .signIn:
            break
        }

        let savedPassword = purpose == .resetPassword || purpose == .confirmSignUp ? password : nil
        let found = try await adopt(user, fallbackEmail: normalized, password: savedPassword)
        beginSession(for: found)
        if rememberWithBiometrics, savedPassword != nil {
            rememberBiometricSignIn()
        } else if purpose == .resetPassword {
            disableBiometricSignIn()
        }
        return outcome
    }

    // MARK: Phone codes

    /// Texts a sign-in code. Off until an SMS provider is set up (`AuthFeatures.phoneCodes`).
    func requestPhoneCode(phone: String) async throws {
        guard AuthFeatures.phoneCodes, let cloud else { throw AuthError.methodNotEnabled }
        let normalized = PhoneNormalizer.normalize(phone)
        guard PhoneNormalizer.isValid(normalized) else { throw AuthError.invalidPhone }
        guard !isWorking else { throw AuthError.busy }
        isWorking = true
        defer { isWorking = false }
        await finishPendingSignOut()
        try await cloud.sendPhoneCode(to: normalized)
    }

    func verifyPhoneCode(phone: String, code: String) async throws {
        guard AuthFeatures.phoneCodes, let cloud else { throw AuthError.methodNotEnabled }
        let normalized = PhoneNormalizer.normalize(phone)
        let digits = code.filter(\.isNumber)
        guard (6...10).contains(digits.count) else { throw AuthError.codeInvalid }
        try ensureNotLockedOut()
        guard !isWorking else { throw AuthError.busy }
        isWorking = true
        defer { isWorking = false }
        await finishPendingSignOut()
        let user: CloudUser
        do {
            user = try await cloud.verifyPhone(code: digits, phone: normalized)
        } catch AuthError.codeInvalid {
            registerFailure()
            throw lockoutError() ?? AuthError.codeInvalid
        }
        failedAttempts = 0
        beginSession(for: try await adopt(user, fallbackEmail: "", password: nil))
    }

    // MARK: Password for passwordless accounts

    /// Adds a password to an account that signs in with Apple, a passkey or
    /// email codes. The current session proves who it is.
    func setPassword(_ new: String) async throws {
        guard let cloud, let current = account else { throw AuthError.accountUnavailable }
        guard !current.email.isEmpty else { throw AuthError.methodNotEnabled }
        if let issue = PasswordPolicy.validate(new, email: current.email) { throw AuthError.weakPassword(issue) }
        guard !isWorking else { throw AuthError.busy }
        isWorking = true
        defer { isWorking = false }
        try await cloud.updatePassword(to: new)
        let salt = PasswordHasher.randomSalt()
        let hash = await PasswordHasher.derive(password: new, salt: salt, iterations: PasswordHasher.iterations)
        do {
            try vault.save(
                CredentialRecord(accountID: current.id, salt: salt, hash: hash, iterations: PasswordHasher.iterations),
                forEmail: current.email)
        } catch {
            throw AuthError.storageFailure
        }
        accountHasPassword = true
    }

    // MARK: Reset from the lock screen

    /// Signs out and opens "Forgot password" for this account's email.
    func signOutToResetPassword() {
        requestedResetEmail = account?.email
        signOut(keepingBiometricSignIn: false)
    }

    /// The email the sign-in screen should reset, once.
    func consumeResetRequest() -> String? {
        defer { requestedResetEmail = nil }
        return requestedResetEmail
    }

    /// Creates or updates the on-device account for a server identity. The
    /// server's user ID is the local account ID, so one person is one account
    /// on every device.
    private func adopt(
        _ user: CloudUser, fallbackEmail: String, password: String?,
        fullName: String? = nil, appleUserID: String? = nil
    ) async throws -> DuovaAccount {
        let email = EmailNormalizer.normalize(user.email ?? fallbackEmail)
        var all = loadAccounts()
        var found: DuovaAccount
        if let index = all.firstIndex(where: { $0.id == user.id }) {
            found = all[index]
            let previous = found.email
            found.email = email
            if let appleUserID { found.appleUserID = appleUserID }
            if previous != email, !previous.isEmpty { vault.remove(forEmail: previous) }
            all[index] = found
        } else {
            let name = (fullName?.isEmpty == false ? fullName : nil)
                ?? (email.isEmpty ? String(localized: "Duova User") : Self.defaultName(from: email))
            found = DuovaAccount(
                id: user.id, email: email, name: name, createdAt: .now,
                appleUserID: appleUserID, termsAcceptedAt: .now)
            all.append(found)
        }
        do {
            if let password, !email.isEmpty {
                let salt = PasswordHasher.randomSalt()
                let hash = await PasswordHasher.derive(
                    password: password, salt: salt, iterations: PasswordHasher.iterations)
                try vault.save(
                    CredentialRecord(accountID: found.id, salt: salt, hash: hash, iterations: PasswordHasher.iterations),
                    forEmail: email)
            }
            try store.save(all, name: Name.accounts)
        } catch {
            throw AuthError.storageFailure
        }
        return found
    }

    // MARK: Biometric sign-in

    /// What Face ID / Touch ID unlocks: the session set aside at sign-out,
    /// never the password. Accounts kept on the device (previews and tests)
    /// have no session, so the biometric check alone opens them.
    private struct BiometricPayload: Codable {
        var accountID: UUID
        var email: String
        var refreshToken: String?
    }

    private var biometricSignInWanted: Bool {
        store.load(Bool.self, name: Name.biometricWanted) ?? false
    }

    /// Signed in: whether sign-out will keep the session for Face ID / Touch ID.
    /// Signed out: whether a kept session is waiting.
    func refreshBiometricSignIn() {
        biometricSignInReady = biometricKind.isBiometric
            && (account != nil ? biometricSignInWanted : BiometricSignInVault.exists())
    }

    private func rememberBiometricSignIn() {
        guard biometricKind.isBiometric else { return }
        try? store.save(true, name: Name.biometricWanted)
        refreshBiometricSignIn()
    }

    /// Earlier versions kept the account password behind biometrics. That
    /// copy is deleted; a signed-in person keeps the setting, and their next
    /// sign-out keeps a session instead.
    private func removeOldBiometricSignIn() {
        guard store.load(Int.self, name: Name.biometricFormat) != 2, BiometricSignInVault.exists() else { return }
        BiometricSignInVault.remove()
        if account != nil { try? store.save(true, name: Name.biometricWanted) }
    }

    /// Puts the current session behind Face ID / Touch ID instead of ending
    /// it. Returns false (and changes nothing) if it couldn't be kept safely.
    private func keepSessionForBiometrics(_ account: DuovaAccount) -> Bool {
        guard biometricKind.isBiometric, biometricSignInWanted else { return false }
        let token: String?
        if let cloud {
            guard let current = cloud.currentRefreshToken() else { return false }
            token = current
        } else {
            guard localOnly else { return false }
            token = nil
        }
        do {
            let payload = try JSONEncoder().encode(
                BiometricPayload(accountID: account.id, email: account.email, refreshToken: token))
            try BiometricSignInVault.save(try store.seal(payload, context: "biometric-signin"))
            try store.save(2, name: Name.biometricFormat)
        } catch {
            BiometricSignInVault.remove()
            return false
        }
        cloud?.forgetSessionLocally()
        return true
    }

    /// Turns off Face ID / Touch ID sign-in.
    func disableBiometricSignIn() {
        BiometricSignInVault.remove()
        store.remove(name: Name.biometricWanted)
        refreshBiometricSignIn()
    }

    /// Signs back in with the session kept at sign-out, after a successful
    /// biometric check. The kept session is used once; the next sign-out keeps
    /// a new one.
    func signInWithBiometrics() async -> BiometricResult {
        guard phase == .signedOut, !isWorking else { return .cancelled }
        let reason = String(localized: "Sign in to Duova with \(biometricKind.title).")
        switch await BiometricSignInVault.read(reason: reason) {
        case .cancelled:
            return .cancelled
        case .missing:
            refreshBiometricSignIn()
            return .unavailable
        case .failed:
            return .failed(String(localized: "\(biometricKind.title) failed. Use password."))
        case .data(let sealed):
            guard let plain = try? store.open(sealed, context: "biometric-signin"),
                  let payload = try? JSONDecoder().decode(BiometricPayload.self, from: plain)
            else {
                disableBiometricSignIn()
                return .failed(String(localized: "Use password to reset \(biometricKind.title)."))
            }
            isWorking = true
            defer { isWorking = false }
            do {
                if let token = payload.refreshToken {
                    guard let cloud else { return .unavailable }
                    await finishPendingSignOut()
                    let user = try await cloud.resumeSession(refreshToken: token)
                    guard user.id == payload.accountID else {
                        await cloud.signOut()
                        disableBiometricSignIn()
                        return .failed(String(localized: "Saved sign-in outdated. Use password."))
                    }
                    BiometricSignInVault.remove()
                    beginSession(for: try await adopt(user, fallbackEmail: payload.email, password: nil))
                } else {
                    guard localOnly, let found = loadAccounts().first(where: { $0.id == payload.accountID }) else {
                        disableBiometricSignIn()
                        return .failed(String(localized: "Saved sign-in outdated. Use password."))
                    }
                    BiometricSignInVault.remove()
                    beginSession(for: found)
                }
                return .success
            } catch AuthError.wrongCredentials {
                disableBiometricSignIn()
                return .failed(String(localized: "Saved sign-in outdated. Use password."))
            } catch let error as AuthError {
                // Kept for next time: the session may still be good once back online.
                return .failed(error.errorDescription ?? String(localized: "Something went wrong. Try again."))
            } catch {
                return .failed(String(localized: "Something went wrong. Try again."))
            }
        }
    }

    // MARK: Sign in with Apple

    /// Completes Sign in with Apple. Apple shares the email and name only the
    /// first time, so a new account is created from them then; afterwards the
    /// stable Apple user ID finds it. Continuing with Apple accepts the Terms.
    func signInWithApple(
        userID: String, email: String?, fullName: PersonNameComponents?,
        identityToken: Data?, rawNonce: String
    ) async throws {
        guard let cloud = try accountService() else {
            try signInWithAppleOnDevice(userID: userID, email: email, fullName: fullName)
            return
        }
        guard let identityToken, let token = String(data: identityToken, encoding: .utf8) else {
            throw AuthError.signInFailed
        }
        guard !isWorking else { throw AuthError.busy }
        isWorking = true
        defer { isWorking = false }
        await finishPendingSignOut()
        let user = try await cloud.signInWithApple(idToken: token, rawNonce: rawNonce)
        let formatted = fullName.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) } ?? ""
        let found = try await adopt(
            user, fallbackEmail: email ?? "", password: nil,
            fullName: formatted, appleUserID: userID)
        beginSession(for: found)
    }

    private func signInWithAppleOnDevice(userID: String, email: String?, fullName: PersonNameComponents?) throws {
        if let link = loadLinks().first(where: { $0.kind == .apple && $0.key == userID }),
           let found = loadAccounts().first(where: { $0.id == link.accountID }) {
            beginSession(for: found)
            return
        }

        let normalized = email.map { EmailNormalizer.normalize($0) } ?? ""
        let accounts = loadAccounts()
        // Apple has verified this address, so it can join an existing account that uses it.
        if !normalized.isEmpty, let existing = accounts.first(where: { $0.email == normalized }) {
            var updated = existing
            updated.appleUserID = userID
            try saveLink(IdentityLink(kind: .apple, key: userID, accountID: existing.id))
            try saveAccount(updated)
            beginSession(for: updated)
            return
        }

        let formatted = fullName.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) } ?? ""
        let name = formatted.isEmpty
            ? (normalized.isEmpty ? String(localized: "Duova User") : Self.defaultName(from: normalized))
            : formatted
        let created = DuovaAccount(
            id: UUID(), email: normalized, name: name, createdAt: .now,
            appleUserID: userID, termsAcceptedAt: .now)
        do {
            try store.save(accounts + [created], name: Name.accounts)
            try saveLink(IdentityLink(kind: .apple, key: userID, accountID: created.id))
        } catch {
            throw AuthError.storageFailure
        }
        beginSession(for: created)
    }

    /// Signs out if the Apple ID was disconnected from Duova in Settings.
    func verifyAppleCredential() async {
        guard let userID = account?.appleUserID else { return }
        let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID)
        if state == .revoked || state == .notFound {
            removeLinks { $0.kind == .apple && $0.key == userID }
            if !accountHasPassword && !hasPasskey(for: account?.id) { signOut(keepingBiometricSignIn: false) }
        }
    }

    // MARK: Passkeys

    /// Creates an account protected by a new passkey (no password).
    func signUpWithPasskey(email: String, acceptedTerms: Bool) async throws {
        guard cloud == nil else { throw AuthError.passkeyUnavailable }
        guard localOnly else { throw AuthError.serviceUnavailable }
        let normalized = EmailNormalizer.normalize(email)
        guard EmailNormalizer.isValid(normalized) else { throw AuthError.invalidEmail }
        guard acceptedTerms else { throw AuthError.termsNotAccepted }
        guard vault.record(forEmail: normalized) == nil,
              !loadAccounts().contains(where: { $0.email == normalized })
        else { throw AuthError.emailInUse }
        guard !isWorking else { throw AuthError.busy }
        isWorking = true
        defer { isWorking = false }

        let id = UUID()
        let registration: PasskeyAuthenticator.Registration
        do {
            registration = try await passkeys.register(userID: Data(id.uuidString.utf8), name: normalized)
        } catch {
            throw Self.passkeyError(error)
        }
        let created = DuovaAccount(
            id: id, email: normalized, name: Self.defaultName(from: normalized), createdAt: .now,
            termsAcceptedAt: .now)
        do {
            try store.save(loadAccounts() + [created], name: Name.accounts)
            try saveLink(IdentityLink(
                kind: .passkey, key: registration.credentialID.base64EncodedString(), accountID: id))
        } catch {
            throw AuthError.storageFailure
        }
        beginSession(for: created)
    }

    func signInWithPasskey() async throws {
        guard !isWorking else { throw AuthError.busy }
        isWorking = true
        defer { isWorking = false }

        if let cloud = try accountService() {
            await finishPendingSignOut()
            let user = try await cloud.signInWithPasskey()
            let found = try await adopt(user, fallbackEmail: "", password: nil)
            beginSession(for: found)
            return
        }

        let assertion: PasskeyAuthenticator.Assertion
        do {
            assertion = try await passkeys.assert()
        } catch {
            throw Self.passkeyError(error)
        }
        let key = assertion.credentialID.base64EncodedString()
        guard let link = loadLinks().first(where: { $0.kind == .passkey && $0.key == key }),
              String(data: assertion.userID, encoding: .utf8) == link.accountID.uuidString,
              let found = loadAccounts().first(where: { $0.id == link.accountID })
        else { throw AuthError.noAccountForPasskey }
        beginSession(for: found)
    }

    private static func passkeyError(_ error: Error) -> Error {
        if let error = error as? AuthError { return error }
        if let error = error as? ASAuthorizationError, error.code == .canceled { return CancellationError() }
        return AuthError.passkeyUnavailable
    }

    private func hasPasskey(for id: UUID?) -> Bool {
        guard let id else { return false }
        return loadLinks().contains { $0.kind == .passkey && $0.accountID == id }
    }

    /// Deletes an account that has no password, after a Face ID / Touch ID / passcode check.
    func deletePasswordlessAccount() async -> BiometricResult {
        guard let account, !accountHasPassword else { return .unavailable }
        let result = await BiometricAuthenticator.authenticate(
            reason: String(localized: "Confirm to delete your Duova account."))
        guard result == .success else { return result }
        if let cloud {
            guard !isWorking else { return .failed(AuthError.busy.errorDescription ?? "") }
            isWorking = true
            defer { isWorking = false }
            do {
                // The server only deletes for a freshly issued session.
                try await cloud.refreshSession()
                try await cloud.deleteAccount()
            } catch {
                return .failed((error as? AuthError)?.errorDescription ?? String(localized: "Couldn't delete. Try again."))
            }
        } else if !localOnly {
            return .unavailable
        }
        eraseAccount(account)
        return .success
    }

    /// Reloads the signed-in account's passkeys from the server.
    func refreshPasskeys() async {
        guard let cloud, account != nil else { cloudPasskeys = []; return }
        cloudPasskeys = (try? await cloud.passkeys()) ?? cloudPasskeys
    }

    /// Adds a passkey to the signed-in account.
    func addPasskey() async throws {
        guard let cloud, account != nil else { throw AuthError.passkeyUnavailable }
        try await cloud.registerPasskey()
        await refreshPasskeys()
    }

    func removePasskey(_ id: UUID) async throws {
        guard let cloud else { throw AuthError.passkeyUnavailable }
        try await cloud.deletePasskey(id)
        await refreshPasskeys()
    }

    // MARK: Cloud session

    /// Reads what the server supports, then checks that the stored session is
    /// still accepted. Offline, the person stays signed in; only a definite
    /// "this session is gone" from the server signs them out.
    func verifyCloudSession() async {
        guard let cloud else { return }
        capabilities = await cloud.capabilities()
        guard let current = account else { return }
        switch await cloud.sessionState() {
        case .invalid:
            signOut(keepingBiometricSignIn: false)
        case .unknown:
            break
        case .valid(let user):
            guard user.id == current.id else { signOut(keepingBiometricSignIn: false); return }
            await mirrorServerEmail(user, into: current)
            await refreshPasskeys()
        }
    }

    /// An email change completes on the server after the new inbox confirms
    /// it; follow it here.
    private func mirrorServerEmail(_ user: CloudUser, into current: DuovaAccount) async {
        guard let serverEmail = user.email.map(EmailNormalizer.normalize), !serverEmail.isEmpty,
              serverEmail != current.email else { return }
        var updated = current
        updated.email = serverEmail
        if let record = vault.record(forEmail: current.email) {
            try? vault.save(record, forEmail: serverEmail)
            vault.remove(forEmail: current.email)
        }
        try? saveAccount(updated)
    }

    // MARK: Private cloud data

    private var privateStore: PrivateDataStore? {
        DuovaBackend.client.map { PrivateDataStore(client: $0) }
    }

    private func nameIsCustomized(_ account: DuovaAccount) -> Bool {
        account.name != Self.defaultName(from: account.email)
    }

    /// Keeps the display name in step with its encrypted copy in the cloud.
    /// Runs once this device has the account's keys (`DeviceKeyring`). A name
    /// this device can't open is never overwritten.
    func syncPrivateName() async {
        guard let store = privateStore, let current = account else { return }
        guard let state = try? await store.displayName(for: current.id) else { return }
        switch state {
        case .name(let remote):
            if remote != current.name, !nameIsCustomized(current) {
                var updated = current
                updated.name = remote
                try? saveAccount(updated)
            } else if remote != current.name {
                _ = try? await store.saveDisplayName(current.name, for: current.id)
            }
        case .empty:
            if nameIsCustomized(current) {
                _ = try? await store.saveDisplayName(current.name, for: current.id)
            }
        case .sealedElsewhere:
            break
        }
    }

    // MARK: Links

    private func loadLinks() -> [IdentityLink] {
        store.load([IdentityLink].self, name: Name.links) ?? []
    }

    private func saveLink(_ link: IdentityLink) throws {
        var links = loadLinks().filter { !($0.kind == link.kind && $0.key == link.key) }
        links.append(link)
        try store.save(links, name: Name.links)
    }

    private func removeLinks(where predicate: (IdentityLink) -> Bool) {
        let links = loadLinks().filter { !predicate($0) }
        try? store.save(links, name: Name.links)
    }

    // MARK: Session

    /// Signs out on this device. With Face ID / Touch ID sign-in on, the
    /// session is kept behind biometrics instead of ended.
    func signOut() {
        signOut(keepingBiometricSignIn: true)
    }

    private func signOut(keepingBiometricSignIn keep: Bool) {
        let kept = keep && account.map(keepSessionForBiometrics) == true
        store.remove(name: Name.session)
        endSession()
        if let cloud {
            cloudPasskeys = []
            if !kept {
                let previous = pendingSignOut
                pendingSignOut = Task {
                    await previous?.value
                    await cloud.signOut()
                }
            }
        }
    }

    private func finishPendingSignOut() async {
        guard let pending = pendingSignOut else { return }
        await pending.value
        if pendingSignOut == pending { pendingSignOut = nil }
    }

    /// Deletes the account on Duova's servers (the sign-in identity and, with
    /// it, every row of its data), then everything on this device. Nothing
    /// local is erased unless the server confirmed the deletion.
    func deleteAccount(password: String) async throws {
        guard let account else { throw AuthError.accountUnavailable }
        if let cloud = try accountService() {
            guard !isWorking else { throw AuthError.busy }
            isWorking = true
            defer { isWorking = false }
            // Checks the password with the server, and gets the fresh session deletion needs.
            do {
                try await cloud.verify(email: account.email, password: password)
            } catch AuthError.wrongCredentials {
                throw AuthError.wrongPassword
            }
            try await cloud.deleteAccount()
        } else {
            guard await checkPassword(password) else { throw AuthError.wrongPassword }
        }
        eraseAccount(account)
    }

    private func eraseAccount(_ account: DuovaAccount) {
        vault.remove(forEmail: account.email)
        let remaining = loadAccounts().filter { $0.id != account.id }
        try? store.save(remaining, name: Name.accounts)
        removeLinks { $0.accountID == account.id }
        // The account's website sessions (one store per launched service) go
        // too. Their identifiers are read before the encrypted names are gone.
        let webStores = ServiceSessionRegistry.identifiers(for: account.id, store: store)
        Task.detached {
            for id in webStores { try? await WKWebsiteDataStore.remove(forIdentifier: id) }
        }
        store.removeAll(containing: account.id.uuidString)
        store.remove(name: Name.session)
        KeychainKeyProvider().removeKey(for: account.id)
        KeychainKeyProvider.vault.removeKey(for: account.id)
        DeviceIdentity.remove(for: account.id)
        endSession()
        disableBiometricSignIn()
    }

    // MARK: App Lock

    /// Prompts for Touch ID / Face ID / passcode and unlocks on success.
    func unlockWithBiometrics() async -> BiometricResult {
        guard phase == .locked else { return .success }
        let kind = biometricKind
        let reason = String(localized: "Unlock Duova with \(kind.title).")
        let result = await BiometricAuthenticator.authenticate(reason: reason)
        if result == .success { phase = .active }
        return result
    }

    /// Fallback when biometrics are unavailable or declined: the account password.
    func unlockWithPassword(_ password: String) async throws {
        guard phase == .locked else { return }
        try ensureNotLockedOut()
        guard !isWorking else { throw AuthError.busy }
        isWorking = true
        defer { isWorking = false }
        guard await checkPassword(password) else {
            registerFailure()
            throw lockoutError() ?? AuthError.wrongPassword
        }
        failedAttempts = 0
        phase = .active
    }

    /// Turns App Lock on (after a successful check, so the user can't lock themselves out) or off.
    func setAppLock(enabled: Bool) async -> BiometricResult {
        guard account != nil else { return .unavailable }
        var updated = settings
        if enabled {
            let kind = biometricKind
            let result = await BiometricAuthenticator.authenticate(
                reason: String(localized: "Confirm with \(kind.title) to turn on App Lock."))
            guard result == .success else { return result }
        }
        updated.appLockEnabled = enabled
        persist(settings: updated)
        return .success
    }

    func setLockTimeout(_ timeout: LockTimeout) {
        var updated = settings
        updated.lockTimeout = timeout
        persist(settings: updated)
    }

    func sceneDidEnterBackground(now: Date = .now) {
        backgroundedAt = now
    }

    func sceneDidBecomeActive(now: Date = .now) {
        defer { backgroundedAt = nil }
        guard phase == .active, settings.appLockEnabled, let backgroundedAt else { return }
        guard let limit = settings.lockTimeout.seconds else { return }
        if now.timeIntervalSince(backgroundedAt) >= limit {
            phase = .locked
        }
    }

    // MARK: Profile

    func updateName(_ name: String) throws {
        guard var current = account else { throw AuthError.accountUnavailable }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        current.name = trimmed.isEmpty ? Self.defaultName(from: current.email) : trimmed
        try saveAccount(current)
        if let store = privateStore, nameIsCustomized(current) {
            let id = current.id, saved = current.name
            Task { _ = try? await store.saveDisplayName(saved, for: id) }
        }
    }

    /// Changes the account email. On Duova's servers the new address must be
    /// confirmed from its inbox first, so the change finishes later and this
    /// returns `.confirmationSent`.
    @discardableResult
    func changeEmail(to newEmail: String, password: String) async throws -> EmailChangeOutcome {
        guard let current = account else { throw AuthError.accountUnavailable }
        let normalized = EmailNormalizer.normalize(newEmail)
        guard EmailNormalizer.isValid(normalized) else { throw AuthError.invalidEmail }
        guard normalized != current.email else { return .applied }
        try ensureNotLockedOut()
        guard !isWorking else { throw AuthError.busy }
        isWorking = true
        defer { isWorking = false }

        if let cloud = try accountService() {
            do {
                try await cloud.verify(email: current.email, password: password)
            } catch AuthError.wrongCredentials {
                registerFailure()
                throw lockoutError() ?? AuthError.wrongPassword
            }
            failedAttempts = 0
            try await cloud.requestEmailChange(to: normalized)
            return .confirmationSent
        }

        guard vault.record(forEmail: normalized) == nil else { throw AuthError.emailInUse }
        guard let record = vault.record(forEmail: current.email) else { throw AuthError.accountUnavailable }
        try await verify(password, against: record)

        var updated = current
        updated.email = normalized
        do {
            try vault.save(record, forEmail: normalized)
            try saveAccount(updated)
            vault.remove(forEmail: current.email)
        } catch {
            vault.remove(forEmail: normalized)
            throw AuthError.storageFailure
        }
        disableBiometricSignIn()
        return .applied
    }

    func changePassword(current: String, new: String) async throws {
        guard let account else { throw AuthError.accountUnavailable }
        if let issue = PasswordPolicy.validate(new, email: account.email) { throw AuthError.weakPassword(issue) }
        try ensureNotLockedOut()
        guard !isWorking else { throw AuthError.busy }
        isWorking = true
        defer { isWorking = false }

        if let cloud = try accountService() {
            do {
                try await cloud.verify(email: account.email, password: current)
            } catch AuthError.wrongCredentials {
                registerFailure()
                throw lockoutError() ?? AuthError.wrongPassword
            }
            failedAttempts = 0
            try await cloud.updatePassword(to: new)
        } else {
            guard let record = vault.record(forEmail: account.email) else { throw AuthError.accountUnavailable }
            try await verify(current, against: record)
        }

        let salt = PasswordHasher.randomSalt()
        let hash = await PasswordHasher.derive(password: new, salt: salt, iterations: PasswordHasher.iterations)
        do {
            try vault.save(
                CredentialRecord(accountID: account.id, salt: salt, hash: hash, iterations: PasswordHasher.iterations),
                forEmail: account.email)
        } catch {
            throw AuthError.storageFailure
        }
    }

    /// Stores a new profile photo (already-chosen image data), or removes it when `nil`.
    func setAvatar(_ data: Data?) throws {
        guard let account else { throw AuthError.accountUnavailable }
        if let data {
            guard let prepared = AvatarProcessor.prepare(data) else { throw AuthError.storageFailure }
            do {
                try store.saveData(prepared, name: Name.avatar(account.id))
            } catch {
                throw AuthError.storageFailure
            }
            avatar = UIImage(data: prepared)
        } else {
            store.remove(name: Name.avatar(account.id))
            avatar = nil
        }
    }

    // MARK: Internals

    private func restoreSession() {
        guard let session = store.load(SessionRecord.self, name: Name.session),
              let found = loadAccounts().first(where: { $0.id == session.accountID }),
              cloud != nil
                || localOnly && (vault.record(forEmail: found.email)?.accountID == found.id
                    || loadLinks().contains(where: { $0.accountID == found.id }))
        else {
            store.remove(name: Name.session)
            return
        }
        account = found
        accountHasPassword = vault.record(forEmail: found.email)?.accountID == found.id
        sessionStartedAt = session.startedAt
        settings = store.load(AccountSettings.self, name: Name.settings(found.id)) ?? AccountSettings()
        loadAvatar(for: found)
        phase = settings.appLockEnabled ? .locked : .active
    }

    private func beginSession(for found: DuovaAccount) {
        failedAttempts = 0
        lockedOutUntil = nil
        let started = Date.now
        account = found
        accountHasPassword = vault.record(forEmail: found.email)?.accountID == found.id
        sessionStartedAt = started
        settings = store.load(AccountSettings.self, name: Name.settings(found.id)) ?? AccountSettings()
        try? store.save(SessionRecord(accountID: found.id, startedAt: started), name: Name.session)
        loadAvatar(for: found)
        phase = .active
        refreshBiometricSignIn()
    }

    private func endSession() {
        account = nil
        accountHasPassword = false
        sessionStartedAt = nil
        settings = AccountSettings()
        avatar = nil
        backgroundedAt = nil
        phase = .signedOut
        refreshBiometricSignIn()
    }

    private func loadAvatar(for found: DuovaAccount) {
        avatar = store.loadData(name: Name.avatar(found.id)).flatMap { UIImage(data: $0) }
    }

    private func loadAccounts() -> [DuovaAccount] {
        store.load([DuovaAccount].self, name: Name.accounts) ?? []
    }

    private func saveAccount(_ updated: DuovaAccount) throws {
        var all = loadAccounts()
        if let index = all.firstIndex(where: { $0.id == updated.id }) {
            all[index] = updated
        } else {
            all.append(updated)
        }
        do {
            try store.save(all, name: Name.accounts)
        } catch {
            throw AuthError.storageFailure
        }
        account = updated
    }

    private func persist(settings updated: AccountSettings) {
        guard let account else { return }
        try? store.save(updated, name: Name.settings(account.id))
        settings = updated
    }

    private func verify(_ password: String, against record: CredentialRecord) async throws {
        let derived = await PasswordHasher.derive(password: password, salt: record.salt, iterations: record.iterations)
        guard PasswordHasher.constantTimeEqual(derived, record.hash) else {
            registerFailure()
            throw lockoutError() ?? AuthError.wrongPassword
        }
        failedAttempts = 0
    }

    private func checkPassword(_ password: String) async -> Bool {
        guard let account, let record = vault.record(forEmail: account.email) else { return false }
        let derived = await PasswordHasher.derive(password: password, salt: record.salt, iterations: record.iterations)
        return PasswordHasher.constantTimeEqual(derived, record.hash)
    }

    /// Duova's servers, or nil for accounts kept on this device (previews and
    /// tests only). A build without its server configuration can't sign in.
    private func accountService() throws -> CloudAuthService? {
        if let cloud { return cloud }
        guard localOnly else { throw AuthError.serviceUnavailable }
        return nil
    }

    private func ensureNotLockedOut() throws {
        if let until = lockedOutUntil {
            if until > .now { throw AuthError.tooManyAttempts(until: until) }
            lockedOutUntil = nil
        }
    }

    private func registerFailure() {
        failedAttempts += 1
        if failedAttempts >= Self.maxFailedAttempts {
            failedAttempts = 0
            lockedOutUntil = Date.now.addingTimeInterval(Self.lockoutSeconds)
        }
    }

    private func lockoutError() -> AuthError? {
        guard let until = lockedOutUntil, until > .now else { return nil }
        return .tooManyAttempts(until: until)
    }

    /// "jane.doe@example.com" becomes "Jane Doe".
    static func defaultName(from email: String) -> String {
        let local = email.split(separator: "@").first.map(String.init) ?? email
        let words = local.split(whereSeparator: { ".-_+".contains($0) }).map { String($0) }
        let name = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        return name.isEmpty ? String(localized: "Duova User") : name
    }
}
