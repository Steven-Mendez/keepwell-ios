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
    func unconfirmingPutsTheDraftBackAsItWasBalancesIncluded() async throws {
        let store = InMemoryStore(sample: sample)
        let today = SampleData.defaultReferenceDate
        let planned = try #require(sample.transactions.first { !$0.isConfirmed && $0.date > today })
        let account = try #require(sample.accounts.first { $0.id == planned.accountID })
        let balance = { () async -> [Money] in
            await Balances.balance(of: account, transactions: store.fetchTransactions(in: nil), calendar: Fixtures.calendar)
        }
        let before = await balance()
        try await DefaultConfirmPlannedTransactionUseCase(transactions: store, now: { today }).execute(id: planned.id)
        #expect(await balance() != before)
        try await DefaultUnconfirmTransactionUseCase(transactions: store).execute(id: planned.id, plannedDate: planned.date)
        #expect(await store.fetchTransactions(in: nil).first { $0.id == planned.id } == planned)
        #expect(await balance() == before)
    }

    @Test
    func unconfirmingLeavesADraftAloneAndFailsForAnUnknownMovement() async throws {
        let store = InMemoryStore(sample: sample)
        let planned = try #require(sample.transactions.first { !$0.isConfirmed })
        try await DefaultUnconfirmTransactionUseCase(transactions: store).execute(id: planned.id, plannedDate: .distantPast)
        #expect(await store.fetchTransactions(in: nil).first { $0.id == planned.id } == planned)
        let missing = UUID()
        await #expect(throws: DomainError.notFound(missing)) {
            try await DefaultUnconfirmTransactionUseCase(transactions: store).execute(id: missing, plannedDate: .now)
        }
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
