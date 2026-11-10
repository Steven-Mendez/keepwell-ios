import AuthenticationServices
import CloudAccountDomain
import Foundation

/// Runs the system passkey sheet for an assertion and hands back what the server verifies. The
/// relying party is the web app's host, which this app declares as an associated domain
/// (`webcredentials:`), so passkeys made on the web work here.
@MainActor
public final class PasskeyAuthorizer: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<PasskeyAssertion, any Error>?

    override public init() {}

    public func assert(_ options: PasskeyOptions) async throws -> PasskeyAssertion {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.relyingParty)
        let request = provider.createCredentialAssertionRequest(challenge: options.challenge)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    public func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization,
    ) {
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            continuation?.resume(throwing: CloudAccountError.server(code: "passkey_unexpected", requestID: nil))
            continuation = nil
            return
        }
        continuation?.resume(returning: PasskeyAssertion(
            credentialID: credential.credentialID,
            clientDataJSON: credential.rawClientDataJSON,
            authenticatorData: credential.rawAuthenticatorData ?? Data(),
            signature: credential.signature ?? Data(),
            userHandle: credential.userID,
        ))
        continuation = nil
    }

    public func authorizationController(controller _: ASAuthorizationController, didCompleteWithError error: any Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    public func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}
