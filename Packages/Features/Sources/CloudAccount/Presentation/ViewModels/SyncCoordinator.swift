import CloudAccountDomain
import Foundation
import Observation

/// When to sync: on start, back in the foreground, a moment after each local change and every
/// minute while active, one round at a time. Errors back off; `needsPlan` and a lost session stop
/// it until `resume()` (after /me changes or the person signs in again). A first sync that finds
/// data on both sides pauses it until the person keeps one (`resolve(_:)`).
@MainActor
@Observable
public final class SyncCoordinator {
    public private(set) var state = SyncState.idle(lastSync: nil, pending: 0)
    /// Rounds that have ended, failed ones included. Signing in during onboarding waits for the
    /// next one to know whether the account had data to bring down.
    public private(set) var completedRounds = 0
    /// The sheet that asks which data to keep. "Decide later" closes it; the conflict stays.
    public var isChoosingData = false
    /// The choice being carried out, for the sheet's progress.
    public private(set) var isResolving = false
    /// The signed-in account, so the engine can tell a first sync with it.
    public var accountID: String?

    private let run: @Sendable (String?) async throws(CloudAccountError) -> SyncRoundOutcome
    private let resolveChoice: @Sendable (SyncChoice, String?) async throws(CloudAccountError) -> Void
    private let status: @Sendable () async -> (lastSync: Date?, pending: Int)
    private var task: Task<Void, Never>?
    private var periodic: Task<Void, Never>?
    private var running = false
    private var again = false
    private var halted = false
    private var heldForSetup = false
    private var failures = 0

    public init(
        run: @escaping @Sendable (String?) async throws(CloudAccountError) -> SyncRoundOutcome,
        resolve: @escaping @Sendable (SyncChoice, String?) async throws(CloudAccountError) -> Void = { _, _ in },
        status: @escaping @Sendable () async -> (lastSync: Date?, pending: Int),
    ) {
        self.run = run
        resolveChoice = resolve
        self.status = status
    }

    /// For callers whose rounds never stop for a choice (tests, previews).
    public convenience init(
        run: @escaping @Sendable () async throws(CloudAccountError) -> Void,
        status: @escaping @Sendable () async -> (lastSync: Date?, pending: Int),
    ) {
        self.init(
            run: { _ throws(CloudAccountError) in
                try await run()
                return .synced
            },
            status: status,
        )
    }

    /// The conflict waiting for a choice, if any.
    public var conflict: SyncConflict? {
        if case let .needsChoice(conflict) = state {
            conflict
        } else {
            nil
        }
    }

    /// "Choose which data to keep" in Settings: the sheet again.
    public func reviewChoice() {
        if conflict != nil {
            isChoosingData = true
        }
    }

    /// "Decide later": sync stays paused and the app keeps working on this iPhone.
    public func decideLater() {
        isChoosingData = false
    }

    /// Keeps one side, then sync goes on as usual. Returns whether it worked; on failure the
    /// conflict stays, so the person can try again.
    @discardableResult
    public func resolve(_ choice: SyncChoice) async -> Bool {
        guard let conflict, !isResolving else { return false }
        isResolving = true
        defer { isResolving = false }
        while running {
            try? await Task.sleep(for: .milliseconds(100))
        }
        running = true
        state = .syncing
        let error = await attempt { () async throws(CloudAccountError) in
            try await self.resolveChoice(choice, self.accountID)
        }
        running = false
        completedRounds += 1
        guard error == nil else {
            state = .needsChoice(conflict)
            return false
        }
        isChoosingData = false
        halted = false
        failures = 0
        let current = await status()
        state = .idle(lastSync: current.lastSync, pending: current.pending)
        // A change made while the choice ran waited for it.
        if again {
            again = false
            trigger(after: 0)
        }
        return true
    }

    public func start() {
        guard periodic == nil else { return }
        periodic = Task { [weak self] in
            while !Task.isCancelled {
                self?.trigger(after: 0)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Signed out or lost the plan. A pending choice belonged to that session: the next sign-in
    /// looks at both sides again.
    public func stop() {
        periodic?.cancel()
        periodic = nil
        task?.cancel()
        if conflict != nil {
            state = .idle(lastSync: nil, pending: 0)
            isChoosingData = false
            halted = false
        }
    }

    public func resume() {
        // A pending choice isn't something /me or a new sign-in settles.
        guard conflict == nil else { return }
        halted = false
        failures = 0
        trigger(after: 0)
    }

    /// A local change: sync in a couple of seconds, coalescing a burst of edits.
    public func changed() {
        trigger(after: 2)
    }

    /// Onboarding after signing in to an account without data: nothing syncs while the person sets
    /// up, so half a setup never reaches the account (keepwell-web does the same). The first sync
    /// already ran, so what setup saves goes up once it's released.
    public func holdForSetup() {
        heldForSetup = true
        task?.cancel()
    }

    public func releaseAfterSetup() {
        guard heldForSetup else { return }
        heldForSetup = false
        trigger(after: 0)
    }

    public func trigger(after seconds: Double) {
        guard !halted, !heldForSetup else { return }
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.round()
        }
    }

    private func round() async {
        if running {
            again = true
            return
        }
        running = true
        state = .syncing
        var outcome = SyncRoundOutcome.synced
        let account = accountID
        let error = await attempt { () async throws(CloudAccountError) in
            outcome = try await self.run(account)
        }
        if error == nil {
            failures = 0
        }
        running = false
        let current = await status()
        completedRounds += 1
        switch error {
        case nil:
            if case let .needsChoice(conflict) = outcome {
                state = .needsChoice(conflict)
                halted = true
                isChoosingData = true
                return
            }
            state = .idle(lastSync: current.lastSync, pending: current.pending)
            if again {
                again = false
                trigger(after: 0)
            }
        case .needsPlan:
            state = .needsPlan
            halted = true
        case .signedOut:
            state = .signedOut
            halted = true
        case .unreachable:
            state = .offline(pending: current.pending)
            backOff()
        case let .server(_, requestID):
            state = .failed(requestID: requestID)
            backOff()
        case .notInvited, .invalidInvitation:
            state = .signedOut
            halted = true
        case .purchaseBelongsToAnotherAccount, .storeFailed:
            // Not sync errors; listed so a new case is a compile error here, not a silent default.
            state = .failed(requestID: nil)
            backOff()
        }
    }

    /// The work's failure, if any (typed: `catch` gives a `CloudAccountError`).
    private func attempt(_ work: () async throws(CloudAccountError) -> Void) async -> CloudAccountError? {
        do {
            try await work()
            return nil
        } catch {
            return error
        }
    }

    private func backOff() {
        failures += 1
        trigger(after: min(300, 2 * pow(2, Double(failures))))
    }
}
