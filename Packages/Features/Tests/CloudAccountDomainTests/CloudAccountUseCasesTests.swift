import CloudAccountDomain
import Foundation
import Testing

private actor FakeRepository: CloudAccountRepository {
    var user: CloudAccountUser?
    var currentError: CloudAccountError?
    var everywhereError: CloudAccountError?
    private(set) var calls: [String] = []

    init(user: CloudAccountUser? = nil, currentError: CloudAccountError? = nil, everywhereError: CloudAccountError? = nil) {
        self.user = user
        self.currentError = currentError
        self.everywhereError = everywhereError
    }

    func currentUser() async throws(CloudAccountError) -> CloudAccountUser? {
        calls.append("current")
        if let currentError {
            throw currentError
        }
        return user
    }

    func signIn(with credential: AppleCredential) async throws(CloudAccountError) -> CloudAccountUser {
        calls.append("signIn:\(credential.rawNonce)")
        let signedIn = CloudAccountUser(id: "u1", name: "Ana", email: "ana@example.com")
        user = signedIn
        return signedIn
    }

    func signOut() async {
        calls.append("signOut")
        user = nil
    }

    func signOutEverywhere() async throws(CloudAccountError) {
        calls.append("everywhere")
        if let everywhereError {
            throw everywhereError
        }
    }

    func deleteAccount() async throws(CloudAccountError) {
        calls.append("delete")
    }
}

@Suite("Cloud account use cases")
struct CloudAccountUseCasesTests {
    @Test
    func aRevokedSessionReadsAsSignedOut() async throws {
        let repository = FakeRepository(currentError: .signedOut)
        let user = try await DefaultLoadCloudAccountUseCase(repository: repository).execute()
        #expect(user == nil)
    }

    @Test
    func beingOfflineIsNotBeingSignedOut() async {
        let repository = FakeRepository(currentError: .unreachable)
        await #expect(throws: CloudAccountError.unreachable) {
            try await DefaultLoadCloudAccountUseCase(repository: repository).execute()
        }
    }

    @Test
    func signingInSendsTheRawNonce() async throws {
        let repository = FakeRepository()
        let user = try await DefaultSignInWithAppleUseCase(repository: repository).execute(AppleCredential(idToken: "t", rawNonce: "n1"))
        #expect(user.email == "ana@example.com")
        #expect(await repository.calls == ["signIn:n1"])
    }

    @Test
    func signingOutEverywhereRevokesOthersBeforeThisIPhone() async throws {
        let repository = FakeRepository(user: CloudAccountUser(id: "u1", name: "", email: "a@b.c"))
        try await DefaultSignOutUseCase(repository: repository).execute(everywhere: true)
        #expect(await repository.calls == ["everywhere", "signOut"])
    }

    @Test
    func aFailedSignOutEverywhereKeepsThisSessionToRetry() async {
        let repository = FakeRepository(user: CloudAccountUser(id: "u1", name: "", email: "a@b.c"), everywhereError: .unreachable)
        await #expect(throws: CloudAccountError.unreachable) {
            try await DefaultSignOutUseCase(repository: repository).execute(everywhere: true)
        }
        #expect(await repository.calls == ["everywhere"])
    }
}
