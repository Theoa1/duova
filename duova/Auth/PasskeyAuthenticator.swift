import AuthenticationServices
import UIKit

/// Creates and uses passkeys for Duova through the system passkey sheet.
///
/// Passkeys are bound to a web domain (the relying party). The app must list it
/// under Associated Domains (`webcredentials:`) and the domain must serve an
/// `apple-app-site-association` file naming this app; until both are in place
/// the system refuses the request and Duova reports passkeys as unavailable.
final class PasskeyAuthenticator: NSObject {
    static let relyingParty = "duova.app"

    struct Registration {
        var credentialID: Data
    }

    struct Assertion {
        var credentialID: Data
        var userID: Data
    }

    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private var controller: ASAuthorizationController?

    func register(userID: Data, name: String) async throws -> Registration {
        let challenge = Self.randomChallenge()
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: Self.relyingParty)
        let request = provider.createCredentialRegistrationRequest(challenge: challenge, name: name, userID: userID)
        let authorization = try await perform(request)
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
              Self.clientData(credential.rawClientDataJSON, matches: challenge)
        else { throw AuthError.signInFailed }
        return Registration(credentialID: credential.credentialID)
    }

    func assert() async throws -> Assertion {
        let challenge = Self.randomChallenge()
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: Self.relyingParty)
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        let authorization = try await perform(request)
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion,
              Self.clientData(credential.rawClientDataJSON, matches: challenge)
        else { throw AuthError.signInFailed }
        return Assertion(credentialID: credential.credentialID, userID: credential.userID)
    }

    private func perform(_ request: ASAuthorizationRequest) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<ASAuthorization, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        controller = nil
    }

    private static func randomChallenge() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    /// The signed client data must echo the challenge this request generated.
    private static func clientData(_ json: Data, matches challenge: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let echoed = object["challenge"] as? String
        else { return false }
        let expected = challenge.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return echoed == expected
    }
}

extension PasskeyAuthenticator: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        finish(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        finish(.failure(error))
    }
}

extension PasskeyAuthenticator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return window }
        guard let scene = scenes.first else { preconditionFailure("Passkey requests start from a visible window.") }
        return UIWindow(windowScene: scene)
    }
}
