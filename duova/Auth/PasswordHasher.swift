import CommonCrypto
import Foundation
import Security

/// One-way password protection. Passwords are never stored or encrypted
/// reversibly: only a salted PBKDF2-HMAC-SHA256 hash is kept, and that hash is
/// itself sealed by `SecureStore` before it reaches the Keychain.
nonisolated enum PasswordHasher {
    /// Work factor for newly created hashes (OWASP guidance for PBKDF2-HMAC-SHA256).
    static let iterations = 600_000
    static let saltLength = 16
    static let outputLength = 32

    static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: saltLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // SecRandomCopyBytes only fails if the system RNG is unavailable; fall back to the system generator.
            for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        }
        return Data(bytes)
    }

    /// Derives the hash on a background executor so the UI never stalls.
    @concurrent
    static func derive(password: String, salt: Data, iterations: Int) async -> Data {
        // Canonical form, so the same visible password always hashes the same way.
        let secret = Array(password.precomposedStringWithCompatibilityMapping.utf8)
        // An empty password can never match a stored hash (policy requires a minimum length).
        guard !secret.isEmpty else { return Data() }
        var output = [UInt8](repeating: 0, count: outputLength)
        _ = secret.withUnsafeBufferPointer { secretBuffer in
            salt.withUnsafeBytes { saltBuffer in
                secretBuffer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: secret.count) { secretPointer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        secretPointer,
                        secret.count,
                        saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        &output,
                        output.count
                    )
                }
            }
        }
        return Data(output)
    }

    /// Compares without leaking where the first difference is.
    static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (a, b) in zip(lhs, rhs) { difference |= a ^ b }
        return difference == 0
    }
}
