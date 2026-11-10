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

private final class SignOuts: SignOutUseCase, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int {
        lock.withLock { count }
    }

    func execute(everywhere _: Bool) async throws(CloudAccountError) {
        lock.withLock { count += 1 }
    }
}

private struct StubDelete: DeleteCloudAccountUseCase {
    var error: CloudAccountError?
    func execute() async throws(CloudAccountError) {
        if let error {
            throw error
        }
    }
}

/// Counts sync rounds the coordinator runs.
private final class SyncRuns: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func run() {
        lock.withLock { count += 1 }
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
        CloudAccountViewModel(load: StubLoad(result: loaded), signIn: signIn, signOut: SignOuts(), delete: delete)
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
    func theInvitationGoesWithTheFirstSignInAndIsForgottenAfter() async {
        let signIn = RecordingSignIn(result: .success(ana))
        let model = model(signIn: signIn)
        model.invitation = "  ABCDE-FGHJK "
        _ = model.prepareAppleRequest()
        await model.completeAppleSignIn(idToken: "jwt")
        #expect(await signIn.credentials.first?.invitation == "ABCDE-FGHJK")
        #expect(model.invitation.isEmpty)
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

    /// "Delete all my data" while signed in: the account's copy must not come back down.
    @Test
    func erasingThisIPhoneSignsOutOfTheAccount() async {
        let signOuts = SignOuts()
        let model = CloudAccountViewModel(
            load: StubLoad(result: .success(ana)), signIn: RecordingSignIn(result: .success(ana)), signOut: signOuts, delete: StubDelete(),
        )
        await model.refresh()
        #expect(model.isSignedIn)
        #expect(await model.signOutBeforeErasing())
        #expect(model.state == .signedOut)
        #expect(signOuts.value == 1)
    }

    @Test
    func erasingThisIPhoneWhileSignedOutDoesNothingToTheAccount() async {
        let signOuts = SignOuts()
        let model = CloudAccountViewModel(
            load: StubLoad(result: .success(nil)), signIn: RecordingSignIn(result: .success(ana)), signOut: signOuts, delete: StubDelete(),
        )
        await model.refresh()
        #expect(await model.signOutBeforeErasing())
        #expect(signOuts.value == 0)
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

    @Test
    func aMissingInvitationAsksForTheCodeUntilASignInWorks() async {
        let model = model(signIn: RecordingSignIn(result: .failure(.notInvited)))
        await model.refresh()
        _ = model.prepareAppleRequest()
        await model.completeAppleSignIn(idToken: "jwt")
        #expect(model.needsInvitation)

        let invited = self.model(signIn: RecordingSignIn(result: .failure(.invalidInvitation)))
        _ = invited.prepareAppleRequest()
        await invited.completeAppleSignIn(idToken: "jwt")
        #expect(invited.needsInvitation)
    }

    /// Someone who started without an account signs in later from Settings: the session starts
    /// sync, which pushes the outbox of everything recorded locally.
    @Test
    func signingInLaterFromSettingsStartsSync() async throws {
        let runs = SyncRuns()
        let sync = SyncCoordinator(run: { runs.run() }, status: { (nil, 0) })
        let syncing = CloudAccountUser(id: "u1", name: "Ana", email: "ana@example.com", capabilities: ["cloud_sync"])
        let model = CloudAccountViewModel(
            load: StubLoad(result: .success(nil)),
            signIn: RecordingSignIn(result: .success(syncing)),
            signOut: SignOuts(),
            delete: StubDelete(),
            sync: sync,
        )
        await model.refresh()
        #expect(model.state == .signedOut)
        #expect(sync.completedRounds == 0)

        _ = model.prepareAppleRequest()
        await model.completeAppleSignIn(idToken: "jwt")
        #expect(model.state == .signedIn(syncing))
        for _ in 0 ..< 200 where sync.completedRounds == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(runs.value >= 1)
        #expect(sync.completedRounds >= 1)

        // Signing out goes back to local use: sync stops and nothing else changes.
        await model.signOut(everywhere: false)
        #expect(model.state == .signedOut)
    }
}
