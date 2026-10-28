import CryptoKit
import Foundation
import Security

/// The nonce that ties a Sign in with Apple response to the request that made
/// it. Apple receives the SHA-256 of the raw value; the server receives the
/// raw value and checks they match, so a stolen identity token can't be replayed.
nonisolated enum AppleNonce {
    static func makeRaw(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // Never fall back to something predictable.
            bytes = (0..<length).map { _ in UInt8.random(in: .min ... .max) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ raw: String) -> String {
        SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
