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
        if !email.isEmpty { return email }
        return appleUserID != nil ? String(localized: "Signed in with Apple") : String(localized: "Signed in with phone")
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
    /// The account was created and a confirmation email was sent. The person
    /// signs in after opening its link.
    case confirmationSent
}

/// Why a one-time code was emailed. Codes are only ever held in memory while
/// they're typed, then sent once to the server; they're never stored.
enum EmailCodePurpose: Equatable {
    /// Confirm a new email-and-password account.
    case confirmSignUp
    /// Sign in without a password.
    case signIn
    /// Create a passwordless account, then add a passkey to it.
    case passkeySignUp
    /// Prove the email, then set a new password.
    case resetPassword
}

/// Where a one-time code goes.
enum CodeChannel: Equatable {
    case email
    case phone
}

/// Sign-in options that exist in the app but are switched off until the
/// server side is ready.
enum AuthFeatures {
    /// Texting codes needs an SMS provider (such as Twilio) set up in Supabase.
    static let phoneCodes = false
}

nonisolated enum PhoneNormalizer {
    /// "+1 (555) 010-0000" becomes "+15550100000".
    static func normalize(_ phone: String) -> String {
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter(\.isNumber)
        return trimmed.hasPrefix("+") ? "+" + digits : digits
    }

    /// International format: a plus sign, then 8 to 15 digits.
    static func isValid(_ normalized: String) -> Bool {
        normalized.hasPrefix("+") && (8...15).contains(normalized.count - 1)
    }
}

enum CodeOutcome: Equatable {
    case signedIn
    case passkeyAdded
    /// Signed in, but the passkey wasn't created (cancelled or unavailable).
    case passkeySkipped
}

enum EmailChangeOutcome: Equatable {
    /// The email was changed immediately (accounts kept on this device only).
    case applied
    /// A confirmation was sent to the new address; it changes once confirmed.
    case confirmationSent
}

nonisolated enum PasswordIssue: Equatable {
    case tooShort
    case tooLong
    case sameAsEmail

    var message: String {
        switch self {
        case .tooShort: String(localized: "Use \(PasswordPolicy.minimumLength)+ characters.")
        case .tooLong: String(localized: "Use \(PasswordPolicy.maximumLength) characters max.")
        case .sameAsEmail: String(localized: "Password can't match email.")
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
    case invalidPhone
    case weakPassword(PasswordIssue)
    /// The account has a password and this wasn't it.
    case wrongPassword
    /// Couldn't tell which part was wrong.
    case wrongCredentials
    case tooManyAttempts(until: Date)
    case emailInUse
    case accountUnavailable
    case storageFailure
    case busy
    case termsNotAccepted
    case passkeyUnavailable
    case noAccountForPasskey
    case signInFailed
    /// The account exists but its email hasn't been confirmed yet.
    case emailNotConfirmed
    /// Duova's servers couldn't be reached.
    case network
    case rateLimited
    /// The server turned this sign-in method off.
    case methodNotEnabled
    /// The server refused with a short message that's safe to show.
    case serverRejected(String)
    /// No account uses this email.
    case noAccount
    case codeInvalid
    case passkeyNotRecognized
    case passkeyExists
    /// Duova's servers aren't configured in this build, so nobody can sign in.
    case serviceUnavailable

    // Messages stay at five words or fewer, and say what to do when possible.
    var errorDescription: String? {
        switch self {
        case .invalidEmail: String(localized: "Enter a valid email.")
        case .invalidPhone: String(localized: "Use format +1 555 010 0000.")
        case .weakPassword(let issue): issue.message
        case .wrongPassword: String(localized: "Wrong password. Try again.")
        case .wrongCredentials: String(localized: "Wrong email or password.")
        case .tooManyAttempts(let until):
            String(localized: "Too many tries. Wait \(max(1, Int(until.timeIntervalSinceNow.rounded(.up))))s.")
        case .emailInUse: String(localized: "Email registered. Sign in instead.")
        case .accountUnavailable: String(localized: "Account unavailable. Sign in again.")
        case .storageFailure: String(localized: "Couldn't save. Unlock device.")
        case .busy: String(localized: "Still working on it.")
        case .termsNotAccepted: String(localized: "Accept the Terms first.")
        case .passkeyUnavailable: String(localized: "Passkeys unavailable here.")
        case .noAccountForPasskey: String(localized: "No account for that passkey.")
        case .signInFailed: String(localized: "Sign-in didn't finish. Retry.")
        case .emailNotConfirmed: String(localized: "Confirm your email first.")
        case .network: String(localized: "No connection. Try again.")
        case .rateLimited: String(localized: "Too many requests. Wait.")
        case .methodNotEnabled: String(localized: "This method isn't enabled.")
        case .serverRejected(let message): message
        case .noAccount: String(localized: "No account uses this email.")
        case .codeInvalid: String(localized: "Code wrong or expired.")
        case .passkeyNotRecognized: String(localized: "Passkey not recognized.")
        case .passkeyExists: String(localized: "Passkey already added.")
        case .serviceUnavailable: String(localized: "Sign-in unavailable. Update Duova.")
        }
    }
}
