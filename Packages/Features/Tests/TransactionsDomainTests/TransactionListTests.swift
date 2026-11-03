import Domain
import DomainSamples
import Foundation
import Testing
@testable import TransactionsDomain

@Suite("Transaction list")
struct TransactionListTests {
    private let sample = SampleData.standard

    @Test
    func listsEverythingNewestFirst() async throws {
        let store = InMemoryStore(sample: sample)
        let list = try await DefaultGetTransactionListUseCase(
            transactions: store, accounts: store, cards: store, categories: store, settings: store,
        ).execute()
        #expect(list.transactions.count == sample.transactions.count)
        #expect(list.transactions.map(\.date) == list.transactions.map(\.date).sorted(by: >))
    }

    @Test
    func plannedMovementsOnlyShowUnderAllOrPlanned() {
        let planned = sample.transactions.filter { !$0.isConfirmed }
        #expect(!planned.isEmpty)
        for transaction in planned {
            #expect(TransactionFilter.all.matches(transaction))
            #expect(TransactionFilter.planned.matches(transaction))
            #expect(!TransactionFilter.expense.matches(transaction))
        }
    }

    @Test
    func kindFiltersMatchConfirmedMovementsOfThatKind() {
        for transaction in sample.transactions where transaction.isConfirmed {
            #expect(TransactionFilter.expense.matches(transaction) == (transaction.kind == .expense))
            #expect(TransactionFilter.income.matches(transaction) == (transaction.kind == .income))
            #expect(TransactionFilter.transfer.matches(transaction) == (transaction.kind == .transfer))
            #expect(!TransactionFilter.planned.matches(transaction))
        }
    }
}
