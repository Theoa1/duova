import LocalAuthentication
import Foundation

/// The strongest local unlock method the device currently offers.
enum BiometricKind: Equatable {
    case touchID
    case faceID
    case opticID
    case passcode
    case unavailable

    /// Name shown to the user. Follows the hardware, so an iPhone Duo with a
    /// side-button sensor says "Touch ID" and a Face ID device says "Face ID".
    var title: String {
        switch self {
        case .touchID: String(localized: "Touch ID")
        case .faceID: String(localized: "Face ID")
        case .opticID: String(localized: "Optic ID")
        case .passcode: String(localized: "Device Passcode")
        case .unavailable: String(localized: "Device Passcode")
        }
    }

    var systemImage: String {
        switch self {
        case .touchID: "touchid"
        case .faceID: "faceid"
        case .opticID: "opticid"
        case .passcode, .unavailable: "lock.fill"
        }
    }

    var isAvailable: Bool { self != .unavailable }

    /// A fingerprint, face or iris sensor (not just the device passcode).
    var isBiometric: Bool { self == .touchID || self == .faceID || self == .opticID }
}

enum BiometricResult: Equatable {
    case success
    /// The user dismissed the prompt. Not an error.
    case cancelled
    case failed(String)
    case unavailable
}

/// Thin wrapper around LocalAuthentication. Biometrics (or the device
/// passcode as the system's own fallback) only unlock Duova on this device.
/// They never replace the account password.
enum BiometricAuthenticator {
    static func availability() -> BiometricKind {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .touchID: return .touchID
            case .faceID: return .faceID
            case .opticID: return .opticID
            default: return .passcode
            }
        }
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) { return .passcode }
        return .unavailable
    }

    static func authenticate(reason: String) async -> BiometricResult {
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Cancel")
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return ok ? .success : .failed(String(localized: "Authentication didn't succeed."))
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel:
                return .cancelled
            case .systemCancel, .appCancel:
                // The system interrupted the prompt (for example the app wasn't
                // in front yet). Not the user's choice, so say so.
                return .failed(String(localized: "Prompt interrupted. Try again."))
            case .biometryLockout:
                return .failed(String(localized: "Too many tries. Use passcode."))
            case .biometryNotAvailable, .passcodeNotSet, .biometryNotEnrolled:
                return .unavailable
            default:
                return .failed(laError.localizedDescription)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
