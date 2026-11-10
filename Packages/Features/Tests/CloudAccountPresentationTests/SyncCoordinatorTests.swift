import CloudAccountDomain
import Foundation
import Testing
@testable import CloudAccountPresentation

/// Records the rounds and choices the coordinator runs.
private final class Engine: @unchecked Sendable {
    private let lock = NSLock()
    private var rounds = 0
    private var choices: [(SyncChoice, String?)] = []
    var outcome = SyncRoundOutcome.synced
    var resolveError: CloudAccountError?

    var roundCount: Int {
        lock.withLock { rounds }
    }

    var resolved: [(SyncChoice, String?)] {
        lock.withLock { choices }
    }

    func round() -> SyncRoundOutcome {
        lock.withLock {
            rounds += 1
            return outcome
        }
    }

    func resolve(_ choice: SyncChoice, _ account: String?) throws(CloudAccountError) {
        let error = lock.withLock {
            choices.append((choice, account))
            return resolveError
        }
        if let error {
            throw error
        }
    }
}

@MainActor
@Suite("Sync coordinator and the first-sync choice")
struct SyncCoordinatorTests {
    private let conflict = SyncConflict(
        device: SyncDataSummary(movements: 12, accounts: 3),
        account: SyncDataSummary(movements: 40, accounts: 2),
    )

    private func coordinator(_ engine: Engine) -> SyncCoordinator {
        let sync = SyncCoordinator(
            run: { _ in engine.round() },
            resolve: { choice, account throws(CloudAccountError) in try engine.resolve(choice, account) },
            status: { (nil, 0) },
        )
        sync.accountID = "u1"
        return sync
    }

    private func waitForRounds(_ sync: SyncCoordinator, _ count: Int) async throws {
        for _ in 0 ..< 300 where sync.completedRounds < count {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test
    func dataOnBothSidesPausesSyncAndAsks() async throws {
        let engine = Engine()
        engine.outcome = .needsChoice(conflict)
        let sync = coordinator(engine)
        sync.trigger(after: 0)
        try await waitForRounds(sync, 1)

        #expect(sync.state == .needsChoice(conflict))
        #expect(sync.conflict == conflict)
        #expect(sync.isChoosingData)

        // Paused: neither a local change, the minute timer nor /me changing runs another round.
        sync.changed()
        sync.resume()
        sync.trigger(after: 0)
        try await Task.sleep(for: .milliseconds(150))
        #expect(engine.roundCount == 1)
    }

    @Test
    func decidingLaterKeepsThePauseAndSettingsCanAskAgain() async throws {
        let engine = Engine()
        engine.outcome = .needsChoice(conflict)
        let sync = coordinator(engine)
        sync.trigger(after: 0)
        try await waitForRounds(sync, 1)

        sync.decideLater()
        #expect(!sync.isChoosingData)
        #expect(sync.conflict == conflict)

        sync.reviewChoice()
        #expect(sync.isChoosingData)
    }

    @Test
    func choosingASideResolvesItAndSyncGoesOn() async throws {
        let engine = Engine()
        engine.outcome = .needsChoice(conflict)
        let sync = coordinator(engine)
        sync.trigger(after: 0)
        try await waitForRounds(sync, 1)
        engine.outcome = .synced

        #expect(await sync.resolve(.keepDevice))
        #expect(engine.resolved.map(\.0) == [.keepDevice])
        #expect(engine.resolved.map(\.1) == ["u1"])
        #expect(sync.conflict == nil)
        #expect(!sync.isChoosingData)

        sync.trigger(after: 0)
        try await waitForRounds(sync, 3)
        #expect(engine.roundCount == 2)
    }

    @Test
    func aFailedChoiceLeavesTheQuestionOpen() async throws {
        let engine = Engine()
        engine.outcome = .needsChoice(conflict)
        engine.resolveError = .unreachable
        let sync = coordinator(engine)
        sync.trigger(after: 0)
        try await waitForRounds(sync, 1)

        #expect(await !sync.resolve(.useAccount))
        #expect(sync.conflict == conflict)
        #expect(sync.isChoosingData)
    }

    /// Onboarding after signing in to an account without data: nothing syncs until setup ends.
    @Test
    func holdsRoundsDuringSetup() async throws {
        let engine = Engine()
        let sync = coordinator(engine)
        sync.holdForSetup()
        sync.trigger(after: 0)
        sync.changed()
        try await Task.sleep(for: .milliseconds(150))
        #expect(engine.roundCount == 0)

        sync.releaseAfterSetup()
        try await waitForRounds(sync, 1)
        #expect(engine.roundCount == 1)
    }

    @Test
    func signingOutDropsTheQuestion() async throws {
        let engine = Engine()
        engine.outcome = .needsChoice(conflict)
        let sync = coordinator(engine)
        sync.trigger(after: 0)
        try await waitForRounds(sync, 1)

        sync.stop()
        #expect(sync.conflict == nil)
        #expect(!sync.isChoosingData)
    }
}

@MainActor
@Suite("Name suggested to onboarding")
struct SuggestedNameTests {
    private struct NoUser: LoadCloudAccountUseCase {
        func execute() async throws(CloudAccountError) -> CloudAccountUser? {
            nil
        }
    }

    private struct SignIn: SignInWithAppleUseCase {
        let user: CloudAccountUser
        func execute(_: AppleCredential) async throws(CloudAccountError) -> CloudAccountUser {
            user
        }
    }

    private struct SignOut: SignOutUseCase {
        func execute(everywhere _: Bool) async throws(CloudAccountError) {}
    }

    private struct Delete: DeleteCloudAccountUseCase {
        func execute() async throws(CloudAccountError) {}
    }

    private func model(_ user: CloudAccountUser) -> CloudAccountViewModel {
        CloudAccountViewModel(load: NoUser(), signIn: SignIn(user: user), signOut: SignOut(), delete: Delete())
    }

    @Test
    func prefersTheNameAppleShared() async {
        let user = CloudAccountUser(id: "u1", name: "Steven Mendez", email: "s@example.com")
        let model = model(user)
        _ = model.prepareAppleRequest()
        await model.completeAppleSignIn(idToken: "jwt", givenName: "Steve")
        #expect(model.suggestedName(for: user) == "Steve")
    }

    @Test
    func otherwiseTheAccountsFirstNameButNeverTheEmail() {
        #expect(model(CloudAccountUser(id: "u1", name: "Steven Mendez", email: "s@example.com"))
            .suggestedName(for: CloudAccountUser(id: "u1", name: "Steven Mendez", email: "s@example.com")) == "Steven")
        let emailOnly = CloudAccountUser(id: "u1", name: "s@example.com", email: "s@example.com")
        #expect(model(emailOnly).suggestedName(for: emailOnly) == nil)
        let nameless = CloudAccountUser(id: "u1", name: "", email: "s@example.com")
        #expect(model(nameless).suggestedName(for: nameless) == nil)
    }
}
