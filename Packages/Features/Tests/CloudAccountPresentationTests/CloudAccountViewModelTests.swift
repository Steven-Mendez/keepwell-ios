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

@MainActor
@Suite("Cloud account view model")
struct CloudAccountViewModelTests {
    private let ana = CloudAccountUser(id: "u1", name: "Ana", email: "ana@example.com")

    @Test
    func appleSeesTheHashAndTheServerTheRawNonce() async throws {
        let signIn = RecordingSignIn(result: .success(ana))
        let model = CloudAccountViewModel(load: StubLoad(result: .success(nil)), signIn: signIn, signOut: StubSignOut())
        let hashed = model.prepareAppleRequest()
        await model.completeAppleSignIn(idToken: "jwt")
        let raw = try #require(await signIn.credentials.first?.rawNonce)
        #expect(hashed == CloudAccountViewModel.sha256(raw))
        #expect(hashed != raw)
        #expect(model.state == .signedIn(ana))
    }

    @Test
    func aNotInvitedAppleIDStaysSignedOutWithTheReason() async {
        let model = CloudAccountViewModel(
            load: StubLoad(result: .success(nil)),
            signIn: RecordingSignIn(result: .failure(.notInvited)),
            signOut: StubSignOut(),
        )
        await model.refresh()
        _ = model.prepareAppleRequest()
        await model.completeAppleSignIn(idToken: "jwt")
        #expect(model.state == .signedOut)
        #expect(model.errorMessage != nil)
    }

    @Test
    func cancellingApplesSheetShowsNoError() {
        let model = CloudAccountViewModel(
            load: StubLoad(result: .success(nil)),
            signIn: RecordingSignIn(result: .success(ana)),
            signOut: StubSignOut(),
        )
        _ = model.prepareAppleRequest()
        model.appleSignInFailed(cancelled: true)
        #expect(model.errorMessage == nil)
    }

    @Test
    func signingOutReturnsToSignedOut() async {
        let model = CloudAccountViewModel(
            load: StubLoad(result: .success(ana)),
            signIn: RecordingSignIn(result: .success(ana)),
            signOut: StubSignOut(),
        )
        await model.refresh()
        #expect(model.state == .signedIn(ana))
        await model.signOut(everywhere: false)
        #expect(model.state == .signedOut)
    }
}
