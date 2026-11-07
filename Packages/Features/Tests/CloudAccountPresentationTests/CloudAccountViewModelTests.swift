import CloudAccountDomain
import Foundation
import Testing
@testable import CloudAccountPresentation

private struct StubLoad: LoadCloudAccountUseCase {
    let result: Result<CloudAccountUser?, CloudAccountError>
    func execute() async throws(CloudAccountError) -> CloudAccountUser? {
        try result.get()
    }
}

private actor RecordingSignIn: SignInWithAppleUseCase {
    var credentials: [AppleCredential] = []
    let result: Result<CloudAccountUser, CloudAccountError>

    init(result: Result<CloudAccountUser, CloudAccountError>) {
        self.result = result
    }

    func execute(_ credential: AppleCredential) async throws(CloudAccountError) -> CloudAccountUser {
        credentials.append(credential)
        return try result.get()
    }
}

private struct StubSignOut: SignOutUseCase {
    func execute(everywhere _: Bool) async throws(CloudAccountError) {}
}

private struct StubDelete: DeleteCloudAccountUseCase {
    var error: CloudAccountError?
    func execute() async throws(CloudAccountError) {
        if let error {
            throw error
        }
    }
}

@MainActor
@Suite("Cloud account view model")
struct CloudAccountViewModelTests {
    private let ana = CloudAccountUser(id: "u1", name: "Ana", email: "ana@example.com")

    private func model(
        loaded: Result<CloudAccountUser?, CloudAccountError> = .success(nil),
        signIn: any SignInWithAppleUseCase = RecordingSignIn(result: .failure(.unreachable)),
        delete: StubDelete = StubDelete(),
    ) -> CloudAccountViewModel {
        CloudAccountViewModel(load: StubLoad(result: loaded), signIn: signIn, signOut: StubSignOut(), delete: delete)
    }

    @Test
    func appleSeesTheHashAndTheServerTheRawNonce() async throws {
        let signIn = RecordingSignIn(result: .success(ana))
        let model = model(signIn: signIn)
        let hashed = model.prepareAppleRequest()
        await model.completeAppleSignIn(idToken: "jwt")
        let raw = try #require(await signIn.credentials.first?.rawNonce)
        #expect(hashed == CloudAccountViewModel.sha256(raw))
        #expect(hashed != raw)
        #expect(model.state == .signedIn(ana))
    }

    @Test
    func aNotInvitedAppleIDStaysSignedOutWithTheReason() async {
        let model = model(signIn: RecordingSignIn(result: .failure(.notInvited)))
        await model.refresh()
        _ = model.prepareAppleRequest()
        await model.completeAppleSignIn(idToken: "jwt")
        #expect(model.state == .signedOut)
        #expect(model.errorMessage != nil)
    }

    @Test
    func cancellingApplesSheetShowsNoError() {
        let model = model()
        _ = model.prepareAppleRequest()
        model.appleSignInFailed(cancelled: true)
        #expect(model.errorMessage == nil)
    }

    @Test
    func signingOutReturnsToSignedOut() async {
        let model = model(loaded: .success(ana))
        await model.refresh()
        #expect(model.state == .signedIn(ana))
        await model.signOut(everywhere: false)
        #expect(model.state == .signedOut)
    }

    @Test
    func deletingTheAccountSignsOut() async {
        let model = model(loaded: .success(ana))
        await model.refresh()
        await model.deleteAccount()
        #expect(model.state == .signedOut)
    }

    @Test
    func aFailedDeletionKeepsTheAccountAndSaysWhy() async {
        let model = model(loaded: .success(ana), delete: StubDelete(error: .unreachable))
        await model.refresh()
        await model.deleteAccount()
        #expect(model.state == .signedIn(ana))
        #expect(model.errorMessage != nil)
    }
}
