import AuthenticationServices
import SwiftUI

/// Apple's own button, wired to the view model's nonce and token exchange. Shared by the sign-in
/// step and the account card in Settings so both sign in the same way.
struct AppleSignInButton: View {
    let viewModel: CloudAccountViewModel
    var label: SignInWithAppleButton.Label = .signIn

    var body: some View {
        SignInWithAppleButton(label) { request in
            request.requestedScopes = [.fullName, .email]
            request.nonce = viewModel.prepareAppleRequest()
        } onCompletion: { result in
            switch result {
            case let .success(authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let data = credential.identityToken,
                      let token = String(data: data, encoding: .utf8)
                else {
                    viewModel.appleSignInFailed(cancelled: false)
                    return
                }
                Task { await viewModel.completeAppleSignIn(idToken: token) }
            case let .failure(error):
                viewModel.appleSignInFailed(cancelled: (error as? ASAuthorizationError)?.code == .canceled)
            }
        }
        .signInWithAppleButtonStyle(.white)
        .disabled(viewModel.isWorking)
    }
}
