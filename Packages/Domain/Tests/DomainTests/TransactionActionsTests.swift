import DomainSamples
import Foundation
import Testing
@testable import Domain

@Suite("Transaction actions")
struct TransactionActionsTests {
    private let sample = SampleData.standard

    @Test
    func confirmingAPlannedMovementMakesItCount() async throws {
        let store = InMemoryStore(sample: sample)
        let planned = try #require(sample.transactions.first { !$0.isConfirmed })
        let today = SampleData.defaultReferenceDate
        try await DefaultConfirmPlannedTransactionUseCase(transactions: store, now: { today }).execute(id: planned.id)
        let saved = try #require(await store.fetchTransactions(in: nil).first { $0.id == planned.id })
        #expect(saved.isConfirmed)
        // A future planned date moves to the day it was confirmed; a past one keeps its date.
        #expect(saved.date == min(planned.date, today))
        #expect(saved.amount == planned.amount)
    }

    @Test
    func confirmingAnUnknownMovementFails() async throws {
        let store = InMemoryStore(sample: sample)
        let missing = UUID()
        await #expect(throws: DomainError.notFound(missing)) {
            try await DefaultConfirmPlannedTransactionUseCase(transactions: store).execute(id: missing)
        }
    }

    @Test
    func deletingRemovesTheMovement() async throws {
        let store = InMemoryStore(sample: sample)
        let first = try #require(sample.transactions.first)
        try await DefaultDeleteTransactionUseCase(transactions: store).execute(id: first.id)
        #expect(await store.fetchTransactions(in: nil).contains { $0.id == first.id } == false)
    }
}
