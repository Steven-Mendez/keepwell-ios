import CloudAccountDomain
import DesignSystem
import SwiftUI

/// The onboarding step after the welcome: sign in to a Keepwell account (Apple, a passkey made on
/// the web, an invitation code for new accounts) or continue without one. One strong action, the
/// alternatives below it and the local path last, quieter, with what it means in one line.
public struct AccountSignInView: View {
    @Bindable private var viewModel: CloudAccountViewModel
    private let isFindingData: Bool
    private let onBack: () -> Void
    private let onContinue: (CloudAccountUser) -> Void
    private let onContinueWithoutAccount: () -> Void
    @State private var showsInvitation = false
    @State private var passkeyAuthorizer = PasskeyAuthorizer()

    /// `onContinue` runs for a session that was already on this iPhone; a fresh sign-in is seen by
    /// the caller through the view model's state. `isFindingData` shows the wait while the
    /// account's data syncs down.
    public init(
        viewModel: CloudAccountViewModel,
        isFindingData: Bool,
        onBack: @escaping () -> Void,
        onContinue: @escaping (CloudAccountUser) -> Void,
        onContinueWithoutAccount: @escaping () -> Void,
    ) {
        self.viewModel = viewModel
        self.isFindingData = isFindingData
        self.onBack = onBack
        self.onContinue = onContinue
        self.onContinueWithoutAccount = onContinueWithoutAccount
    }

    public var body: some View {
        KWScreen(bottom: 32) {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWFlowHeader(.back, action: onBack)
                KWAppIconTile()
                    .padding(.top, KWSpacing.xs)
                Text("Sign in to Keepwell", bundle: #bundle)
                    .kwTextStyle(.titleSm)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Sync your accounts and movements with Keepwell on the web and your other devices.", bundle: #bundle)
                    .font(KWTextStyle.body.font)
                    .foregroundStyle(KWColor.Text.muted)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: KWSpacing.md)
                content
            }
        }
        .task {
            if viewModel.state == .loading {
                await viewModel.refresh()
            }
        }
        .onChange(of: viewModel.needsInvitation) { _, needs in
            if needs {
                showsInvitation = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity)
        case let .signedIn(user):
            signedIn(user)
        case .signedOut:
            signInOptions
        }
    }

    private func signedIn(_ user: CloudAccountUser) -> some View {
        VStack(alignment: .leading, spacing: KWSpacing.sm) {
            KWGroupedCard {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Signed in as", bundle: #bundle)
                        .font(KWTextStyle.captionSm.font.weight(.regular))
                        .foregroundStyle(KWColor.Text.muted)
                    Text(user.name.isEmpty ? user.email : user.name).font(KWTextStyle.body.font)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
            }
            if isFindingData {
                HStack(spacing: KWSpacing.xs) {
                    ProgressView()
                    Text("Looking for your data…", bundle: #bundle)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.Text.muted)
                }
                .frame(maxWidth: .infinity)
                .frame(height: KWComponentMetrics.buttonHeight)
            } else {
                Button { onContinue(user) } label: { Text("Continue", bundle: #bundle) }
                    .buttonStyle(.kw())
            }
        }
    }

    private var signInOptions: some View {
        VStack(alignment: .leading, spacing: KWSpacing.sm) {
            AppleSignInButton(viewModel: viewModel, label: .continue)
                .frame(height: KWComponentMetrics.buttonHeight)
                .clipShape(Capsule())
            if viewModel.canUsePasskeys {
                Button {
                    Task { await viewModel.signInWithPasskey(using: passkeyAuthorizer) }
                } label: {
                    Text("Use a passkey", bundle: #bundle)
                }
                .buttonStyle(.kw(.secondary))
                .disabled(viewModel.isWorking)
            }
            invitation
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.State.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
            orDivider
            Button(action: onContinueWithoutAccount) {
                Text("Continue without an account", bundle: #bundle)
            }
            .buttonStyle(.kw(.surface))
            .disabled(viewModel.isWorking)
            Text("Your data stays only on this iPhone.", bundle: #bundle)
                .font(KWTextStyle.captionSm.font.weight(.regular))
                .foregroundStyle(KWColor.Text.muted)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    /// Accounts are invite-only for new people, while everyone who already has one signs in
    /// without a code, so the field stays folded until asked for or the server wants one.
    @ViewBuilder
    private var invitation: some View {
        if showsInvitation {
            VStack(alignment: .leading, spacing: KWSpacing.xxs) {
                TextField(
                    String(localized: "Invitation code", bundle: #bundle),
                    text: $viewModel.invitation,
                    prompt: Text("Invitation code", bundle: #bundle).foregroundStyle(KWColor.Text.faint),
                )
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(KWTextStyle.body.font.monospaced())
                .kwInputField()
                Text("New accounts need one. Then sign in with Apple or a passkey.", bundle: #bundle)
                    .font(KWTextStyle.captionSm.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Button { showsInvitation = true } label: {
                Text("Have an invitation code?", bundle: #bundle)
            }
            .buttonStyle(.kw(.plain, size: .text))
        }
    }

    private var orDivider: some View {
        HStack(spacing: KWSpacing.sm) {
            KWDivider()
            Text("or", bundle: #bundle)
                .font(KWTextStyle.captionSm.font)
                .foregroundStyle(KWColor.Text.faint)
            KWDivider()
        }
        .padding(.vertical, KWSpacing.xxs)
        .accessibilityHidden(true)
    }
}
