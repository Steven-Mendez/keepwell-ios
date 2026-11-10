import CloudAccountDomain
import Foundation
import Observation

/// When to sync: on start, back in the foreground, a moment after each local change and every
/// minute while active, one round at a time. Errors back off; `needsPlan` and a lost session stop
/// it until `resume()` (after /me changes or the person signs in again).
@MainActor
@Observable
public final class SyncCoordinator {
    public private(set) var state = SyncState.idle(lastSync: nil, pending: 0)
    /// Rounds that have ended, failed ones included. Signing in during onboarding waits for the
    /// next one to know whether the account had data to bring down.
    public private(set) var completedRounds = 0

    private let run: @Sendable () async throws(CloudAccountError) -> Void
    private let status: @Sendable () async -> (lastSync: Date?, pending: Int)
    private var task: Task<Void, Never>?
    private var periodic: Task<Void, Never>?
    private var running = false
    private var again = false
    private var halted = false
    private var failures = 0

    public init(
        run: @escaping @Sendable () async throws(CloudAccountError) -> Void,
        status: @escaping @Sendable () async -> (lastSync: Date?, pending: Int),
    ) {
        self.run = run
        self.status = status
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

    public func stop() {
        periodic?.cancel()
        periodic = nil
        task?.cancel()
    }

    public func resume() {
        halted = false
        failures = 0
        trigger(after: 0)
    }

    /// A local change: sync in a couple of seconds, coalescing a burst of edits.
    public func changed() {
        trigger(after: 2)
    }

    public func trigger(after seconds: Double) {
        guard !halted else { return }
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
        let error = await attempt()
        if error == nil {
            failures = 0
        }
        running = false
        let current = await status()
        completedRounds += 1
        switch error {
        case nil:
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

    /// The round's failure, if any (typed: `catch` gives a `CloudAccountError`).
    private func attempt() async -> CloudAccountError? {
        do {
            try await run()
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
