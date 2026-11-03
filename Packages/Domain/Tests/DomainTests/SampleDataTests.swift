import Foundation
import Testing
@testable import Domain
@testable import DomainSamples

@Suite("Sample data")
struct SampleDataTests {
    private let sample = SampleData.standard

    @Test
    func everyCardAndTransactionPointsAtAnExistingAccount() {
        let accountIDs = Set(sample.accounts.map(\.id))
        #expect(sample.cards.allSatisfy { accountIDs.contains($0.accountID) })
        #expect(sample.transactions.allSatisfy { accountIDs.contains($0.accountID) })
        #expect(sample.transactions.compactMap(\.destinationAccountID).allSatisfy { accountIDs.contains($0) })
    }

    @Test
    func coversTheDesignScenarios() {
        #expect(sample.cards.count == 6)
        #expect(sample.transactions.contains { $0.status == .planned })
        #expect(sample.transactions.contains { $0.kind == .transfer })
        #expect(sample.transactions.contains { $0.isShared })
    }

    @Test
    func netWorthIsComputable() throws {
        let balances = sample.accounts.flatMap {
            Balances.balance(of: $0, transactions: sample.transactions, calendar: .current)
        }
        let total = try NetWorth.total(of: balances, settings: sample.settings.currencies)
        #expect(total.amount > 0)
    }

    @Test
    func inMemoryStoreRoundTrips() async throws {
        let store = InMemoryStore(sample: sample)
        let first = try #require(sample.transactions.first)
        #expect(await store.fetchTransactions(in: nil).count == sample.transactions.count)
        try await store.deleteTransaction(id: first.id)
        await #expect(throws: DomainError.notFound(first.id)) { try await store.deleteTransaction(id: first.id) }
        await store.eraseAll()
        #expect(await store.fetchAccounts().isEmpty)
    }
}
