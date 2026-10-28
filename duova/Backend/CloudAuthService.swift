import AuthenticationServices
import Foundation
import UIKit
@_spi(Experimental) import Supabase

/// The signed-in person as the server knows them.
struct CloudUser: Equatable, Sendable {
    let id: UUID
    let email: String?
    /// Providers linked to the account, such as "email" or "apple".
    let providers: [String]
}

enum CloudSignUpResult: Sendable {
    case signedIn(CloudUser)
    /// The account was created, but the server wants the email confirmed first.
    case confirmationRequired
}

enum CloudSessionState: Sendable {
    case valid(CloudUser)
    /// The server no longer accepts this session (signed out elsewhere, deleted, revoked).
    case invalid
    /// The server couldn't be reached; keep the person signed in offline.
    case unknown
}

/// What this project's Supabase Auth currently allows, read from its public
/// settings. Buttons for a method only appear when the server supports it.
struct CloudCapabilities: Equatable, Sendable {
    var passkeys = false
    var apple = false
    static let none = CloudCapabilities()
}

struct CloudPasskey: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let createdAt: Date
    let lastUsedAt: Date?
}

/// Duova's account service, backed by Supabase Auth. Everything here talks to
/// the server; `AuthController` owns the local session and App Lock around it.
@MainActor
struct CloudAuthService {
    private let client: SupabaseClient

    /// nil when Supabase isn't configured (no `DuovaDev.xcconfig`). Nobody can
    /// sign in then; Duova never quietly switches to on-device accounts.
    init?() {
        guard let client = DuovaBackend.client else { return nil }
        self.client = client
    }

    // MARK: Capabilities

    func capabilities() async -> CloudCapabilities {
        guard let (url, key) = try? DuovaBackend.credentials() else { return .none }
        var request = URLRequest(url: url.appending(path: "auth/v1/settings"))
        request.timeoutInterval = 8
        request.setValue(key, forHTTPHeaderField: "apikey")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .none }
        let external = json["external"] as? [String: Any]
        return CloudCapabilities(
            passkeys: json["passkeys_enabled"] as? Bool ?? false,
            apple: external?["apple"] as? Bool ?? false)
    }

    // MARK: Email and password

    func signUp(email: String, password: String) async throws -> CloudSignUpResult {
        do {
            let response = try await client.auth.signUp(email: email, password: password)
            if let session = response.session {
                return .signedIn(Self.user(session.user))
            }
            // With confirmation required, a repeated sign-up for an existing
            // address comes back as a user with no identities and no error.
            if response.user.identities?.isEmpty == true { throw AuthError.emailInUse }
            return .confirmationRequired
        } catch {
            throw Self.map(error)
        }
    }

    func signIn(email: String, password: String) async throws -> CloudUser {
        do {
            return Self.user(try await client.auth.signIn(email: email, password: password).user)
        } catch {
            throw Self.map(error)
        }
    }

    /// Re-checks a password against the server without changing the session.
    func verify(email: String, password: String) async throws {
        _ = try await signIn(email: email, password: password)
    }

    func updatePassword(to password: String) async throws {
        do { _ = try await client.auth.update(user: UserAttributes(password: password)) } catch {
            throw Self.map(error)
        }
    }

    /// Asks the server to move the account to a new email. The address only
    /// changes after the new inbox confirms it.
    func requestEmailChange(to email: String) async throws {
        do { _ = try await client.auth.update(user: UserAttributes(email: email)) } catch {
            throw Self.map(error)
        }
    }

    // MARK: Email codes

    /// Emails a one-time sign-in code. With `createAccount`, a new account is
    /// made for an unknown address (used to sign up with a passkey).
    func sendSignInCode(to email: String, createAccount: Bool) async throws {
        do { try await client.auth.signInWithOTP(email: email, shouldCreateUser: createAccount) } catch {
            throw Self.map(error)
        }
    }

    func resendSignUpCode(to email: String) async throws {
        do { try await client.auth.resend(email: email, type: .signup) } catch { throw Self.map(error) }
    }

    func sendPasswordReset(to email: String) async throws {
        do { try await client.auth.resetPasswordForEmail(email) } catch { throw Self.map(error) }
    }

    /// Texts a one-time sign-in code to an existing account's phone number.
    func sendPhoneCode(to phone: String) async throws {
        do { try await client.auth.signInWithOTP(phone: phone, shouldCreateUser: false) } catch {
            throw Self.map(error)
        }
    }

    func verifyPhone(code: String, phone: String) async throws -> CloudUser {
        do {
            let response = try await client.auth.verifyOTP(phone: phone, token: code, type: .sms)
            guard response.session != nil else { throw AuthError.codeInvalid }
            return Self.user(response.user)
        } catch {
            throw Self.map(error)
        }
    }

    enum CodeKind { case signUp, signIn, recovery }

    /// Checks an emailed code. The code is used once and never stored.
    func verify(code: String, email: String, kind: CodeKind) async throws -> CloudUser {
        let type: EmailOTPType = switch kind {
        case .signUp: .signup
        case .signIn: .email
        case .recovery: .recovery
        }
        do {
            let response = try await client.auth.verifyOTP(email: email, token: code, type: type)
            guard response.session != nil else { throw AuthError.codeInvalid }
            return Self.user(response.user)
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: Apple

    /// Exchanges a Sign in with Apple identity token. `rawNonce` is the
    /// unhashed nonce whose SHA-256 was sent in the Apple request.
    func signInWithApple(idToken: String, rawNonce: String) async throws -> CloudUser {
        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: rawNonce))
            return Self.user(session.user)
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: Passkeys

    func signInWithPasskey() async throws -> CloudUser {
        do {
            let response = try await client.auth.signInWithPasskey(presentationAnchor: Self.anchor())
            return Self.user(response.user)
        } catch {
            throw Self.map(error)
        }
    }

    /// Adds a passkey to the signed-in account. The server requires an
    /// existing session, so passkeys are added after sign-in, never to sign up.
    @discardableResult
    func registerPasskey() async throws -> CloudPasskey {
        do {
            return Self.passkey(try await client.auth.registerPasskey(presentationAnchor: Self.anchor()))
        } catch {
            throw Self.map(error)
        }
    }

    func passkeys() async throws -> [CloudPasskey] {
        do { return try await client.auth.listPasskeys().map(Self.passkey) } catch {
            throw Self.map(error)
        }
    }

    func deletePasskey(_ id: UUID) async throws {
        do { try await client.auth.deletePasskey(id: id) } catch { throw Self.map(error) }
    }

    // MARK: Session

    /// Validates the stored session with the server, refreshing it if needed.
    func sessionState() async -> CloudSessionState {
        do {
            return .valid(Self.user(try await client.auth.session.user))
        } catch let error as Auth.AuthError {
            switch error {
            case .sessionMissing, .refreshDiscarded:
                return .invalid
            case .api(_, let code, _, let response):
                let definitive: Set<String> = [
                    ErrorCode.refreshTokenNotFound.rawValue, ErrorCode.refreshTokenAlreadyUsed.rawValue,
                    ErrorCode.sessionNotFound.rawValue, ErrorCode.sessionExpired.rawValue,
                    ErrorCode.userNotFound.rawValue, ErrorCode.userBanned.rawValue,
                    ErrorCode.invalidJWT.rawValue, ErrorCode.badJWT.rawValue,
                ]
                if definitive.contains(code.rawValue) || response.statusCode == 401 || response.statusCode == 403 {
                    return .invalid
                }
                return .unknown
            default:
                return .unknown
            }
        } catch {
            return .unknown
        }
    }

    func currentUserID() -> UUID? { client.auth.currentUser?.id }

    /// Ends the session on this device. Other devices stay signed in.
    func signOut() async {
        try? await client.auth.signOut(scope: .local)
    }

    /// Gets a freshly issued access token, which the server requires for
    /// deleting the account.
    func refreshSession() async throws {
        do { _ = try await client.auth.refreshSession() } catch { throw Self.map(error) }
    }

    /// The current session's refresh token, for Face ID / Touch ID sign-in to keep.
    func currentRefreshToken() -> String? {
        client.auth.currentSession?.refreshToken
    }

    /// Takes the session off this device without ending it on the server.
    /// Only after its refresh token is kept safely, or the account is gone.
    func forgetSessionLocally() {
        DuovaAuthStorage.shared.forgetLocally()
    }

    /// Ends every other session of this account, on every device.
    func signOutOtherSessions() async {
        try? await client.auth.signOut(scope: .others)
    }

    /// Resumes a session kept with `currentRefreshToken`. The token is single-use:
    /// the server hands back a new one with the new session.
    func resumeSession(refreshToken: String) async throws -> CloudUser {
        do {
            return Self.user(try await client.auth.refreshSession(refreshToken: refreshToken).user)
        } catch let error as Auth.AuthError {
            if case .api(_, let code, _, _) = error,
               [ErrorCode.refreshTokenNotFound.rawValue, ErrorCode.refreshTokenAlreadyUsed.rawValue,
                ErrorCode.sessionNotFound.rawValue, ErrorCode.sessionExpired.rawValue,
                ErrorCode.userNotFound.rawValue].contains(code.rawValue) {
                throw AuthError.wrongCredentials
            }
            throw Self.map(error)
        } catch {
            throw Self.map(error)
        }
    }

    /// Deletes the account on the server: the Auth user and, by cascade, every
    /// Duova row that belongs to it (schema v5). Needs a session issued in the
    /// last few minutes. Throws unless the server confirmed the deletion.
    func deleteAccount() async throws {
        do {
            try await client.rpc("duova_delete_my_account").execute()
        } catch {
            if error is URLError { throw AuthError.network }
            throw AuthError.serverRejected(String(localized: "Couldn't delete. Try again."))
        }
        // The user no longer exists, so there's no session to end on the server.
        DuovaAuthStorage.shared.forgetLocally()
    }

    // MARK: Helpers

    private static func user(_ user: User) -> CloudUser {
        CloudUser(
            id: user.id, email: user.email,
            providers: (user.identities ?? []).map(\.provider))
    }

    private static func passkey(_ item: PasskeyListItem) -> CloudPasskey {
        CloudPasskey(
            id: item.id, name: item.friendlyName ?? String(localized: "Passkey"),
            createdAt: item.createdAt, lastUsedAt: item.lastUsedAt)
    }

    /// The window the system passkey sheet attaches to.
    private static func anchor() -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        if let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first {
            return window
        }
        if let scene { return UIWindow(windowScene: scene) }
        preconditionFailure("No window scene is available for the passkey sheet.")
    }

    /// Turns server and system errors into messages that are safe to show.
    static func map(_ error: Error) -> Error {
        if error is CancellationError { return error }
        if let error = error as? AuthError { return error }
        if let error = error as? ASAuthorizationError {
            return error.code == .canceled ? CancellationError() : AuthError.signInFailed
        }
        if error is URLError { return AuthError.network }
        if let error = error as? Auth.AuthError {
            switch error {
            case .weakPassword:
                return AuthError.serverRejected(String(localized: "Password too weak."))
            case .api(_, let code, _, let response):
                switch code.rawValue {
                case "invalid_credentials": return AuthError.wrongCredentials
                case "otp_expired": return AuthError.codeInvalid
                case "otp_disabled": return AuthError.noAccount
                case "phone_provider_disabled", "sms_provider_disabled": return AuthError.methodNotEnabled
                case "sms_send_failed": return AuthError.serverRejected(String(localized: "Text didn't send. Retry."))
                case "reauthentication_needed", "reauthentication_not_valid":
                    return AuthError.serverRejected(String(localized: "Sign in again first."))
                case "email_not_confirmed": return AuthError.emailNotConfirmed
                case "email_exists", "user_already_exists": return AuthError.emailInUse
                case "over_request_rate_limit", "over_email_send_rate_limit": return AuthError.rateLimited
                case "provider_disabled", "oauth_provider_not_supported", "passkey_disabled",
                     "feature_disabled": return AuthError.methodNotEnabled
                case "weak_password": return AuthError.serverRejected(String(localized: "Password too weak."))
                case "same_password": return AuthError.serverRejected(String(localized: "Use a new password."))
                case "email_address_invalid", "validation_failed": return AuthError.invalidEmail
                case "email_address_not_authorized": return AuthError.serverRejected(String(localized: "Email not allowed here."))
                case "signup_disabled": return AuthError.serverRejected(String(localized: "Sign-ups are closed."))
                case "webauthn_verification_failed", "webauthn_challenge_expired",
                     "webauthn_challenge_not_found":
                    return AuthError.passkeyNotRecognized
                case "webauthn_credential_exists": return AuthError.passkeyExists
                case "user_banned": return AuthError.signInFailed
                default:
                    return response.statusCode == 429 ? AuthError.rateLimited : AuthError.signInFailed
                }
            case .sessionMissing:
                return AuthError.accountUnavailable
            default:
                return AuthError.signInFailed
            }
        }
        return AuthError.signInFailed
    }
}
