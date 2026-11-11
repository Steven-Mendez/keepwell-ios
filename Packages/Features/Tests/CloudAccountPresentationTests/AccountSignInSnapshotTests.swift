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

private struct SignedIn: LoadCloudAccountUseCase {
    func execute() async throws(CloudAccountError) -> CloudAccountUser? {
        CloudAccountUser(id: "u1", name: "Ana Pérez", email: "ana@example.com", capabilities: ["cloud_sync"])
    }
}

/// A sign-in that never answers, to look at the screen while it waits.
private struct PendingSignIn: SignInWithAppleUseCase {
    func execute(_: AppleCredential) async throws(CloudAccountError) -> CloudAccountUser {
        try? await Task.sleep(for: .seconds(3600))
        throw .unreachable
    }
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
    private func view(_ viewModel: CloudAccountViewModel, isFindingData: Bool = false) -> some View {
        WelcomeView(
            accountChoice: AnyView(
                AccountSignInView(viewModel: viewModel, isFindingData: isFindingData, onContinue: { _ in }, onContinueWithoutAccount: {}),
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

    /// Apple has answered and the API is signing in.
    private func signingIn() async -> (CloudAccountViewModel, Task<Void, Never>) {
        let viewModel = CloudAccountViewModel(load: SignedOut(), signIn: PendingSignIn(), signOut: UnusedSignOut(), delete: UnusedDelete())
        await viewModel.refresh()
        _ = viewModel.prepareAppleRequest()
        let task = Task { await viewModel.completeAppleSignIn(idToken: "jwt") }
        for _ in 0 ..< 100 where !viewModel.isWorking {
            await Task.yield()
        }
        return (viewModel, task)
    }

    private func loadingData() async -> CloudAccountViewModel {
        let viewModel = CloudAccountViewModel(load: SignedIn(), signIn: UnusedSignIn(), signOut: UnusedSignOut(), delete: UnusedDelete())
        await viewModel.refresh()
        return viewModel
    }

    @Test
    func welcomeSigningIn() async {
        let (viewModel, task) = await signingIn()
        #expect(viewModel.isWorking)
        await assertScreenSnapshot(of: view(viewModel))
        task.cancel()
    }

    @Test
    func welcomeSigningInLight() async {
        let (viewModel, task) = await signingIn()
        await assertScreenSnapshot(of: view(viewModel), named: "light", colorScheme: .light)
        task.cancel()
    }

    @Test
    func welcomeLoadingYourData() async {
        await assertScreenSnapshot(of: view(loadingData(), isFindingData: true))
    }

    @Test
    func welcomeLoadingYourDataLight() async {
        await assertScreenSnapshot(of: view(loadingData(), isFindingData: true), named: "light", colorScheme: .light)
    }
}
