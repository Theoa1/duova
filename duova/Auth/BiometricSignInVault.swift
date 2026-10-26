import Foundation
import LocalAuthentication
import Security

/// Optional "sign in with Touch ID / Face ID" support.
///
/// When the user opts in, their sign-in details are sealed with AES-256-GCM
/// (by `SecureStore`) and the sealed blob is stored as a Keychain item that the
/// system will only release after a successful biometric check. The item is
/// bound to this device, requires a passcode, and is invalidated if the
/// enrolled fingerprints or face change. Nothing here is synced or backed up.
nonisolated enum BiometricSignInVault {
    private static let service = "com.duova.biometric-signin"
    private static let account = "last-account"

    enum ReadResult {
        case data(Data)
        case cancelled
        case missing
        case failed
    }

    static func save(_ sealed: Data) throws {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, &error)
        else { throw SecureStoreError.keychain(errSecParam) }

        remove()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessControl as String: access,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
            kSecValueData as String: sealed
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecureStoreError.keychain(status) }
    }

    /// True when a saved sign-in exists. Never shows a prompt.
    static func exists() -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
            kSecUseAuthenticationContext as String: context
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// Shows the system biometric prompt and returns the sealed blob. Runs off
    /// the main actor because the Keychain call blocks while the prompt is up.
    @concurrent
    static func read(reason: String) async -> ReadResult {
        let context = LAContext()
        context.localizedReason = reason
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
            kSecUseAuthenticationContext as String: context,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            if let data = item as? Data { return .data(data) }
            return .failed
        case errSecUserCanceled:
            return .cancelled
        case errSecItemNotFound:
            return .missing
        default:
            return .failed
        }
    }

    static func remove() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemDelete(query as CFDictionary)
    }
}
