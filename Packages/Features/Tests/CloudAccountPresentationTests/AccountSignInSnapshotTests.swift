import CloudAccountDomain
import FeatureTestSupport
import OnboardingPresentation
import SwiftUI
import Testing
@testable import CloudAccountPresentation

private struct SignedOut: LoadCloudAccountUseCase {
    func execute() async throws(CloudAccountError) -> CloudAccountUser? {
        nil
    }
}

private struct UnusedSignIn: SignInWithAppleUseCase {
    func execute(_: AppleCredential) async throws(CloudAccountError) -> CloudAccountUser {
        throw .unreachable
    }
}

private struct UnusedSignOut: SignOutUseCase {
    func execute(everywhere _: Bool) async throws(CloudAccountError) {}
}

private struct UnusedDelete: DeleteCloudAccountUseCase {
    func execute() async throws(CloudAccountError) {}
}

@Suite("Account sign-in snapshots")
@MainActor
struct AccountSignInSnapshotTests {
    private func signedOut() async -> CloudAccountViewModel {
        let viewModel = CloudAccountViewModel(load: SignedOut(), signIn: UnusedSignIn(), signOut: UnusedSignOut(), delete: UnusedDelete())
        await viewModel.refresh()
        return viewModel
    }

    /// The sign-in as people see it: on the onboarding welcome, in place of "Start".
    private func view(_ viewModel: CloudAccountViewModel) -> some View {
        WelcomeView(
            accountChoice: AnyView(
                AccountSignInView(viewModel: viewModel, isFindingData: false, onContinue: { _ in }, onContinueWithoutAccount: {}),
            ),
            onStart: {},
        )
    }

    @Test
    func welcomeWithSignIn() async {
        await assertScreenSnapshot(of: view(signedOut()))
    }

    @Test
    func welcomeWithSignInLight() async {
        await assertScreenSnapshot(of: view(signedOut()), named: "light", colorScheme: .light)
    }
}
