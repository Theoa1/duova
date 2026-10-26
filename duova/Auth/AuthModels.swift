import Foundation

/// A Duova account. Stored only inside the encrypted store (`SecureStore`).
/// Duova accounts are separate from any third-party service account.
struct DuovaAccount: Codable, Identifiable, Equatable {
    let id: UUID
    var email: String
    var name: String
    let createdAt: Date
    /// Stable Apple ID user identifier, for accounts created with Sign in with Apple.
    var appleUserID: String?
    /// When the user accepted the Terms of Use.
    var termsAcceptedAt: Date?

    /// Apple may withhold the email address; show how the account signs in instead.
    var displayEmail: String {
        email.isEmpty ? String(localized: "Signed in with Apple") : email
    }

    /// One or two letters for the monogram avatar.
    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0).uppercased() }.joined()
        if !letters.isEmpty { return letters }
        return email.first.map { String($0).uppercased() } ?? "D"
    }
}

/// Which account is signed in on this device. This record is what makes a
/// sign-in last until the user signs out.
struct SessionRecord: Codable, Equatable {
    var accountID: UUID
    var startedAt: Date
}

/// How long Duova may stay in the background before App Lock asks again.
enum LockTimeout: Int, Codable, CaseIterable, Identifiable {
    case immediately = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case tenMinutes = 600
    case thirtyMinutes = 1800
    case oneHour = 3600
    /// Don't lock again while Duova stays open in the background. A fresh
    /// launch still asks.
    case never = -1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .immediately: String(localized: "Immediately")
        case .oneMinute: String(localized: "1 minute")
        case .fiveMinutes: String(localized: "5 minutes")
        case .tenMinutes: String(localized: "10 minutes")
        case .thirtyMinutes: String(localized: "30 minutes")
        case .oneHour: String(localized: "1 hour")
        case .never: String(localized: "Never")
        }
    }

    /// Seconds in the background before locking, or nil to never re-lock.
    var seconds: TimeInterval? {
        self == .never ? nil : TimeInterval(rawValue)
    }
}

/// Links a passwordless sign-in method to an account (encrypted at rest).
struct IdentityLink: Codable, Equatable {
    enum Kind: String, Codable {
        case apple
        case passkey
    }

    var kind: Kind
    /// Apple user identifier, or the passkey credential ID (base64).
    var key: String
    var accountID: UUID
}

/// Per-account security settings (encrypted at rest).
struct AccountSettings: Codable, Equatable {
    var appLockEnabled = false
    var lockTimeout: LockTimeout = .immediately
}

/// What happened when the sign-in / create-account form was submitted.
/// What the user asked for on the sign-in screen.
enum AuthIntent: Equatable {
    case signIn
    case signUp
}

enum SubmitOutcome: Equatable {
    case signedIn
    case created
}

nonisolated enum PasswordIssue: Equatable {
    case tooShort
    case tooLong
    case sameAsEmail

    var message: String {
        switch self {
        case .tooShort: String(localized: "Use at least \(PasswordPolicy.minimumLength) characters.")
        case .tooLong: String(localized: "Use no more than \(PasswordPolicy.maximumLength) characters.")
        case .sameAsEmail: String(localized: "Your password can't be the same as your email.")
        }
    }
}

nonisolated enum PasswordPolicy {
    static let minimumLength = 8
    static let maximumLength = 128

    static func validate(_ password: String, email: String) -> PasswordIssue? {
        if password.count < minimumLength { return .tooShort }
        if password.count > maximumLength { return .tooLong }
        if password.lowercased() == email.lowercased() { return .sameAsEmail }
        return nil
    }
}

enum EmailNormalizer {
    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isValid(_ normalized: String) -> Bool {
        normalized.wholeMatch(of: /[^\s@]+@[^\s@]+\.[^\s@]{2,}/) != nil
    }
}

enum AuthError: LocalizedError, Equatable {
    case invalidEmail
    case weakPassword(PasswordIssue)
    case wrongPassword
    case tooManyAttempts(until: Date)
    case emailInUse
    case accountUnavailable
    case storageFailure
    case busy
    case termsNotAccepted
    case passkeyUnavailable
    case noAccountForPasskey
    case signInFailed

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            String(localized: "Enter a valid email address.")
        case .weakPassword(let issue):
            issue.message
        case .wrongPassword:
            String(localized: "Wrong email or password.")
        case .tooManyAttempts(let until):
            String(localized: "Too many attempts. Try again in \(max(1, Int(until.timeIntervalSinceNow.rounded(.up)))) seconds.")
        case .emailInUse:
            String(localized: "That email already has an account. Sign in instead.")
        case .accountUnavailable:
            String(localized: "This account couldn't be opened. Please sign in again.")
        case .storageFailure:
            String(localized: "Duova couldn't save your account securely. Make sure your device is unlocked and try again.")
        case .busy:
            String(localized: "Still working on your last request.")
        case .termsNotAccepted:
            String(localized: "Accept the Terms of Use to create your account.")
        case .passkeyUnavailable:
            String(localized: "Passkeys aren't available for Duova on this device yet.")
        case .noAccountForPasskey:
            String(localized: "No Duova account on this device uses that passkey.")
        case .signInFailed:
            String(localized: "Sign-in didn't complete. Try again.")
        }
    }
}
