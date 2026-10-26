import AuthenticationServices
import Foundation
import Observation
import UIKit

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

    init(store: SecureStore = .shared) {
        self.store = store
        vault = CredentialVault(store: store)
        restoreSession()
        refreshBiometricSignIn()
    }

    // MARK: Queries

    func hasAccount(forEmail email: String) -> Bool {
        let normalized = EmailNormalizer.normalize(email)
        guard EmailNormalizer.isValid(normalized) else { return false }
        return vault.record(forEmail: normalized) != nil
    }

    var biometricKind: BiometricKind { BiometricAuthenticator.availability() }

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
        guard !isWorking else { throw AuthError.busy }
        isWorking = true
        defer { isWorking = false }

        let existing = vault.record(forEmail: normalized)
        let outcome: SubmitOutcome

        switch intent {
        case .signIn:
            guard let record = existing else {
                registerFailure()
                throw lockoutError() ?? AuthError.wrongPassword
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

        if rememberWithBiometrics { saveBiometricSignIn(email: normalized, password: password) }
        return outcome
    }

    // MARK: Biometric sign-in

    private struct BiometricPayload: Codable {
        var email: String
        var password: String
    }

    func refreshBiometricSignIn() {
        biometricSignInReady = biometricKind.isBiometric && BiometricSignInVault.exists()
    }

    private func saveBiometricSignIn(email: String, password: String) {
        guard biometricKind.isBiometric else { return }
        do {
            let payload = try JSONEncoder().encode(BiometricPayload(email: email, password: password))
            let sealed = try store.seal(payload, context: "biometric-signin")
            try BiometricSignInVault.save(sealed)
        } catch {
            BiometricSignInVault.remove()
        }
        refreshBiometricSignIn()
    }

    /// Removes the saved Touch ID / Face ID sign-in.
    func disableBiometricSignIn() {
        BiometricSignInVault.remove()
        refreshBiometricSignIn()
    }

    /// Signs in using the saved details after a successful biometric check.
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
            return .failed(String(localized: "\(biometricKind.title) didn't work. Use your password."))
        case .data(let sealed):
            guard let plain = try? store.open(sealed, context: "biometric-signin"),
                  let payload = try? JSONDecoder().decode(BiometricPayload.self, from: plain)
            else {
                disableBiometricSignIn()
                return .failed(String(localized: "Sign in with your password to set \(biometricKind.title) up again."))
            }
            do {
                _ = try await submit(email: payload.email, password: payload.password, intent: .signIn)
                return .success
            } catch AuthError.wrongPassword {
                disableBiometricSignIn()
                return .failed(String(localized: "Your saved sign-in is out of date. Use your password."))
            } catch let error as AuthError {
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
    func signInWithApple(userID: String, email: String?, fullName: PersonNameComponents?) throws {
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
            if !accountHasPassword && !hasPasskey(for: account?.id) { signOut() }
        }
    }

    // MARK: Passkeys

    /// Creates an account protected by a new passkey (no password).
    func signUpWithPasskey(email: String, acceptedTerms: Bool) async throws {
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
        eraseAccount(account)
        return .success
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

    func signOut() {
        store.remove(name: Name.session)
        endSession()
    }

    /// Erases the account and everything stored for it. Requires the password.
    func deleteAccount(password: String) async throws {
        guard let account else { throw AuthError.accountUnavailable }
        guard await checkPassword(password) else { throw AuthError.wrongPassword }
        eraseAccount(account)
    }

    private func eraseAccount(_ account: DuovaAccount) {
        vault.remove(forEmail: account.email)
        let remaining = loadAccounts().filter { $0.id != account.id }
        try? store.save(remaining, name: Name.accounts)
        removeLinks { $0.accountID == account.id }
        store.removeAll(containing: account.id.uuidString)
        store.remove(name: Name.session)
        BiometricSignInVault.remove()
        endSession()
        refreshBiometricSignIn()
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
    }

    func changeEmail(to newEmail: String, password: String) async throws {
        guard let current = account else { throw AuthError.accountUnavailable }
        let normalized = EmailNormalizer.normalize(newEmail)
        guard EmailNormalizer.isValid(normalized) else { throw AuthError.invalidEmail }
        guard normalized != current.email else { return }
        guard vault.record(forEmail: normalized) == nil else { throw AuthError.emailInUse }
        try ensureNotLockedOut()
        guard !isWorking else { throw AuthError.busy }
        isWorking = true
        defer { isWorking = false }
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
    }

    func changePassword(current: String, new: String) async throws {
        guard let account else { throw AuthError.accountUnavailable }
        if let issue = PasswordPolicy.validate(new, email: account.email) { throw AuthError.weakPassword(issue) }
        try ensureNotLockedOut()
        guard !isWorking else { throw AuthError.busy }
        isWorking = true
        defer { isWorking = false }
        guard let record = vault.record(forEmail: account.email) else { throw AuthError.accountUnavailable }
        try await verify(current, against: record)

        let salt = PasswordHasher.randomSalt()
        let hash = await PasswordHasher.derive(password: new, salt: salt, iterations: PasswordHasher.iterations)
        do {
            try vault.save(
                CredentialRecord(accountID: account.id, salt: salt, hash: hash, iterations: PasswordHasher.iterations),
                forEmail: account.email)
        } catch {
            throw AuthError.storageFailure
        }
        disableBiometricSignIn()
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
              vault.record(forEmail: found.email)?.accountID == found.id
                || loadLinks().contains(where: { $0.accountID == found.id })
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
    }

    private func endSession() {
        account = nil
        accountHasPassword = false
        sessionStartedAt = nil
        settings = AccountSettings()
        avatar = nil
        backgroundedAt = nil
        phase = .signedOut
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
