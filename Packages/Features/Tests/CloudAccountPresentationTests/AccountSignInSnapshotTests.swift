import CloudAccountDomain
import FeatureTestSupport
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

    private func view(_ viewModel: CloudAccountViewModel) -> some View {
        AccountSignInView(viewModel: viewModel, isFindingData: false, onBack: {}, onContinue: { _ in }, onContinueWithoutAccount: {})
    }

    @Test
    func signInStep() async {
        await assertScreenSnapshot(of: view(signedOut()))
    }

    @Test
    func signInStepLight() async {
        await assertScreenSnapshot(of: view(signedOut()), named: "light", colorScheme: .light)
    }
}
