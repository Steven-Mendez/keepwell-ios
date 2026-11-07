import AuthenticationServices
import CloudAccountDomain
import DesignSystem
import SwiftUI

/// The Keepwell account inside Settings: Sign in with Apple, or who is signed in with sign-out.
public struct CloudAccountSection: View {
    @Bindable private var viewModel: CloudAccountViewModel
    @State private var isConfirmingEverywhere = false
    @State private var isConfirmingDelete = false

    public init(viewModel: CloudAccountViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            KWSectionHeader(String(localized: "Account", bundle: #bundle)).padding(.top, KWSpacing.xs)
            KWGroupedCard {
                content.padding(.vertical, 14)
            }
            Text("An account syncs this iPhone with Keepwell on the web. Without one, your data stays only here.", bundle: #bundle)
                .font(KWTextStyle.caption.font.weight(.regular))
                .foregroundStyle(KWColor.Text.secondary)
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.State.negative)
            }
        }
        .task { await viewModel.refresh() }
        .confirmationDialog(
            String(localized: "Sign out on all devices?", bundle: #bundle),
            isPresented: $isConfirmingEverywhere,
            titleVisibility: .visible,
        ) {
            Button(role: .destructive) {
                Task { await viewModel.signOut(everywhere: true) }
            } label: {
                Text("Sign out everywhere", bundle: #bundle)
            }
        } message: {
            Text("Every iPhone and browser signed in to this account will need to sign in again.", bundle: #bundle)
        }
        .confirmationDialog(
            String(localized: "Delete your Keepwell account?", bundle: #bundle),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible,
        ) {
            Button(role: .destructive) {
                Task { await viewModel.deleteAccount() }
            } label: {
                Text("Delete account", bundle: #bundle)
            }
        } message: {
            Text(
                // swiftlint:disable:next line_length
                "You're signed out everywhere at once and your synced data is erased from Keepwell's servers. Backups keep it up to 35 more days. What's on this iPhone stays here.",
                bundle: #bundle,
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity)
        case .signedOut:
            SignInWithAppleButton(.signIn) { request in
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
            .frame(height: 48)
            .disabled(viewModel.isWorking)
        case let .signedIn(user):
            VStack(alignment: .leading, spacing: KWSpacing.sm) {
                Text(user.name.isEmpty ? user.email : user.name).font(KWTextStyle.body.font)
                Text(user.email).font(KWTextStyle.caption.font).foregroundStyle(KWColor.Text.secondary)
                Text(syncLine(user)).font(KWTextStyle.caption.font).foregroundStyle(KWColor.Text.secondary)
                HStack {
                    Button {
                        Task { await viewModel.signOut(everywhere: false) }
                    } label: {
                        Text("Sign out", bundle: #bundle)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        isConfirmingEverywhere = true
                    } label: {
                        Text("Sign out on all devices", bundle: #bundle)
                    }
                }
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Text("Delete account", bundle: #bundle)
                }
                .font(KWTextStyle.body.font)
                .disabled(viewModel.isWorking)
            }
        }
    }

    private func syncLine(_ user: CloudAccountUser) -> String {
        guard user.canSync else {
            return String(localized: "Sync isn't included in your plan. Everything keeps working on this iPhone.", bundle: #bundle)
        }
        switch viewModel.sync?.state {
        case .syncing:
            return String(localized: "Syncing…", bundle: #bundle)
        case let .offline(pending) where pending > 0:
            return String(localized: "Offline. Changes sync when you're back online.", bundle: #bundle)
        case .failed, .offline:
            return String(localized: "Couldn't sync. Keepwell will try again.", bundle: #bundle)
        case .needsPlan:
            return String(localized: "Sync isn't included in your plan. Everything keeps working on this iPhone.", bundle: #bundle)
        default:
            return user.earlyAccess.contains("cloud_sync")
                ? String(localized: "Sync included during early access.", bundle: #bundle)
                : String(localized: "Up to date.", bundle: #bundle)
        }
    }
}
