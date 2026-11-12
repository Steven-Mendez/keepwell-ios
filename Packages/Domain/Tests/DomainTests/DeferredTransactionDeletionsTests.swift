import DomainSamples
import Foundation
import Testing
@testable import Domain

/// Deleting a movement with "Undo": the deletion waits for the toast to run out.
@Suite("Deferred transaction deletions")
struct DeferredTransactionDeletionsTests {
    private let sample = SampleData.standard

    /// The store underneath, counting the deletions actually written (each one is a sync event).
    private actor CountingStore: TransactionRepository {
        let base: InMemoryStore
        private(set) var deletes = 0

        init(base: InMemoryStore) {
            self.base = base
        }

        func fetchTransactions(in period: DateInterval?) async throws(DomainError) -> [Transaction] {
            await base.fetchTransactions(in: period)
        }

        func save(_ transaction: Transaction) async throws(DomainError) {
            await base.save(transaction)
        }

        func deleteTransaction(id: UUID) async throws(DomainError) {
            deletes += 1
            try await base.deleteTransaction(id: id)
        }
    }

    private actor MemoryPendingStore: PendingDeletionStore {
        var pending: [UUID: Date] = [:]

        func pendingDeletions() -> [UUID: Date] {
            pending
        }

        func setPendingDeletions(_ pending: [UUID: Date]) {
            self.pending = pending
        }
    }

    /// A toast that never runs out on its own: only `undo` or `flush` end it.
    private static let neverRunsOut: @Sendable (TimeInterval) async throws -> Void = { _ in
        try await Task.sleep(nanoseconds: 3_600_000_000_000)
    }

    @Test
    func deletingAndUndoingLeavesTheMovementIntactWithoutWritingAnything() async throws {
        let counting = CountingStore(base: InMemoryStore(sample: sample))
        let pending = MemoryPendingStore()
        let deletions = DeferredTransactionDeletions(base: counting, store: pending, sleep: Self.neverRunsOut)
        let movement = try #require(sample.transactions.first)
        try await DeferredDeleteTransactionUseCase(deletions: deletions).execute(id: movement.id)
        // Hidden from every screen at once…
        #expect(try await deletions.fetchTransactions(in: nil).contains { $0.id == movement.id } == false)
        #expect(await pending.pending[movement.id] != nil)
        // …and back as it was, with nothing written underneath.
        #expect(await DefaultUndoDeleteTransactionUseCase(deletions: deletions).execute(id: movement.id))
        await deletions.settle()
        #expect(try await deletions.fetchTransactions(in: nil).first { $0.id == movement.id } == movement)
        #expect(await counting.deletes == 0)
        #expect(await pending.pending.isEmpty)
    }

    @Test
    func theDeletionIsWrittenWhenTheUndoWindowRunsOutAndThenCannotBeUndone() async throws {
        let counting = CountingStore(base: InMemoryStore(sample: sample))
        let deletions = DeferredTransactionDeletions(base: counting, store: MemoryPendingStore(), sleep: { _ in })
        let movement = try #require(sample.transactions.first)
        await deletions.schedule(id: movement.id)
        await deletions.settle()
        #expect(await counting.deletes == 1)
        #expect(await counting.base.fetchTransactions(in: nil).contains { $0.id == movement.id } == false)
        #expect(await deletions.undo(id: movement.id) == false)
    }

    @Test
    func aDeletionLeftWaitingByAClosedAppIsWrittenAtLaunch() async throws {
        let base = InMemoryStore(sample: sample)
        let pending = MemoryPendingStore()
        let movement = try #require(sample.transactions.first)
        await DeferredTransactionDeletions(base: base, store: pending, sleep: Self.neverRunsOut).schedule(id: movement.id)
        // The app closes; the next launch finds it overdue.
        let later = Date.now.addingTimeInterval(60)
        let relaunched = DeferredTransactionDeletions(base: base, store: pending, now: { later }, sleep: { _ in })
        await relaunched.resume()
        await relaunched.settle()
        #expect(await base.fetchTransactions(in: nil).contains { $0.id == movement.id } == false)
        #expect(await pending.pending.isEmpty)
    }

    @Test
    func flushWritesEveryWaitingDeletionNow() async throws {
        let base = InMemoryStore(sample: sample)
        let deletions = DeferredTransactionDeletions(base: base, store: MemoryPendingStore(), sleep: Self.neverRunsOut)
        let movement = try #require(sample.transactions.first)
        await deletions.schedule(id: movement.id)
        await deletions.flush()
        #expect(await base.fetchTransactions(in: nil).contains { $0.id == movement.id } == false)
        #expect(await deletions.pendingIDs.isEmpty)
    }

    @Test
    func aMovementAlreadyGoneElsewhereIsForgotten() async throws {
        let base = InMemoryStore(sample: sample)
        let deletions = DeferredTransactionDeletions(base: base, store: MemoryPendingStore(), sleep: Self.neverRunsOut)
        let movement = try #require(sample.transactions.first)
        await deletions.schedule(id: movement.id)
        try await base.deleteTransaction(id: movement.id)
        await deletions.flush()
        #expect(await deletions.pendingIDs.isEmpty)
    }
}
