import Foundation

/// Where the movements waiting to be deleted are remembered, each with when it falls due, so a
/// deletion still happens when the app closes before "Undo" runs out.
public protocol PendingDeletionStore: Sendable {
    func pendingDeletions() async -> [UUID: Date]
    func setPendingDeletions(_ pending: [UUID: Date]) async
}

/// Deletes movements a few seconds late, so "Undo" can take one back without a deletion (or its
/// sync event) ever being written. Until then the movement is only hidden: read through this
/// repository, screens and use cases no longer see it. `resume` finishes, at launch, what a closed
/// app left waiting.
public actor DeferredTransactionDeletions: TransactionRepository {
    /// How long, in seconds, a deletion can be undone; the toast stays on screen as long.
    public static let undoWindow: TimeInterval = 6

    private let base: any TransactionRepository
    private let store: any PendingDeletionStore
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private var due: [UUID: Date] = [:]
    private var timers: [UUID: Task<Void, Never>] = [:]
    /// Deletions being written: too late to undo.
    private var committing: Set<UUID> = []

    public init(
        base: any TransactionRepository,
        store: any PendingDeletionStore,
        now: @escaping @Sendable () -> Date = { .now },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
    ) {
        self.base = base
        self.store = store
        self.now = now
        self.sleep = sleep
    }

    /// Hides the movement now and deletes it once the undo window is over.
    public func schedule(id: UUID) async {
        due[id] = now().addingTimeInterval(Self.undoWindow)
        await persist()
        arm(id)
    }

    /// Takes a deletion back; `false` when it already happened.
    @discardableResult
    public func undo(id: UUID) async -> Bool {
        guard due[id] != nil, !committing.contains(id) else { return false }
        timers.removeValue(forKey: id)?.cancel()
        due[id] = nil
        await persist()
        return true
    }

    /// Picks up the deletions a closed app left waiting and arms each for what is left of its
    /// window: one already due is deleted now.
    public func resume() async {
        for (id, date) in await store.pendingDeletions() where due[id] == nil {
            due[id] = date
            arm(id)
        }
    }

    /// Deletes every waiting movement now (the app is leaving the screen).
    public func flush() async {
        for id in due.keys {
            await commit(id)
        }
    }

    /// Waits for the deletions already armed to run out; for tests.
    public func settle() async {
        for task in timers.values {
            await task.value
        }
    }

    public var pendingIDs: Set<UUID> {
        Set(due.keys)
    }

    private func arm(_ id: UUID) {
        timers[id]?.cancel()
        let wait = max(0, due[id].map { $0.timeIntervalSince(now()) } ?? 0)
        timers[id] = Task { [sleep] in
            do {
                try await sleep(wait)
            } catch {
                return
            }
            await self.commit(id)
        }
    }

    private func commit(_ id: UUID) async {
        guard due[id] != nil, !committing.contains(id) else { return }
        timers[id] = nil
        committing.insert(id)
        defer { committing.remove(id) }
        do {
            try await base.deleteTransaction(id: id)
        } catch .notFound {
            // Already gone (deleted on another device): nothing left to do.
        } catch {
            // Kept for the next launch.
            return
        }
        due[id] = nil
        await persist()
    }

    private func persist() async {
        await store.setPendingDeletions(due)
    }

    // MARK: - TransactionRepository

    public func fetchTransactions(in period: DateInterval?) async throws(DomainError) -> [Transaction] {
        let hidden = due
        return try await base.fetchTransactions(in: period).filter { hidden[$0.id] == nil }
    }

    public func save(_ transaction: Transaction) async throws(DomainError) {
        try await base.save(transaction)
    }

    public func save(_ transactions: [Transaction]) async throws(DomainError) {
        try await base.save(transactions)
    }

    public func deleteTransaction(id: UUID) async throws(DomainError) {
        try await base.deleteTransaction(id: id)
    }
}

/// Deleting from a screen: hidden at once, written when "Undo" runs out.
public struct DeferredDeleteTransactionUseCase: DeleteTransactionUseCase {
    private let deletions: DeferredTransactionDeletions

    public init(deletions: DeferredTransactionDeletions) {
        self.deletions = deletions
    }

    public func execute(id: UUID) async throws(DomainError) {
        await deletions.schedule(id: id)
    }
}

/// Takes back a deletion made with `DeferredDeleteTransactionUseCase` while it can still be undone.
public protocol UndoDeleteTransactionUseCase: Sendable {
    /// `false` when the deletion already happened.
    func execute(id: UUID) async -> Bool
}

public struct DefaultUndoDeleteTransactionUseCase: UndoDeleteTransactionUseCase {
    private let deletions: DeferredTransactionDeletions

    public init(deletions: DeferredTransactionDeletions) {
        self.deletions = deletions
    }

    public func execute(id: UUID) async -> Bool {
        await deletions.undo(id: id)
    }
}
