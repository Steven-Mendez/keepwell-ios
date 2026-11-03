import Domain
import DomainSamples
import Foundation
import Testing
@testable import AccountsDomain

@Suite("Bank account detail")
struct DebitCardDetailTests {
    private typealias IDs = SampleData.IDs

    private func useCases(_ store: InMemoryStore) -> (DefaultGetDebitCardDetailUseCase, DefaultGetAccountsOverviewUseCase) {
        (
            DefaultGetDebitCardDetailUseCase(
                accounts: store, cards: store, transactions: store, categories: store, settings: store,
            ),
            DefaultGetAccountsOverviewUseCase(accounts: store, cards: store, transactions: store, settings: store),
        )
    }

    @Test
    func showsTheCardWithItsAccountsBalance() async throws {
        let store = InMemoryStore(sample: .standard)
        let (detail, overview) = useCases(store)
        let card = try await detail.execute(accountID: IDs.savings)
        let deposit = try #require(try await overview.execute().deposits.first { $0.id == IDs.savings })
        #expect(card.card.id == IDs.savingsDebit)
        #expect(card.account.id == IDs.savings)
        // The same balance the accounts stack prints on the card.
        #expect(card.balance == deposit.balance)
    }

    @Test
    func countsEveryMovementThatDeletingWouldRemove() async throws {
        let store = InMemoryStore(sample: .standard)
        let card = try await useCases(store).0.execute(accountID: IDs.savings)
        let touching = await store.fetchTransactions(in: nil).count { TransactionScope.account(IDs.savings).includes($0) }
        #expect(card.movementCount == touching)
        #expect(touching > 0)
    }

    @Test
    func onlyOpensBankAccounts() async {
        let store = InMemoryStore(sample: .standard)
        await #expect(throws: DomainError.notFound(IDs.mastercard)) {
            try await useCases(store).0.execute(accountID: IDs.mastercard)
        }
        await #expect(throws: DomainError.notFound(IDs.cash)) {
            try await useCases(store).0.execute(accountID: IDs.cash)
        }
    }

    @Test
    func listsTheAccountsLatestConfirmedMovementsNewestFirst() async throws {
        let store = InMemoryStore(sample: .standard)
        let card = try await useCases(store).0.execute(accountID: IDs.savings)
        let latest = card.latestTransactions
        #expect(!latest.isEmpty)
        #expect(latest.count <= DebitCardDetail.latestCount)
        #expect(latest.allSatisfy { $0.isConfirmed && ($0.accountID == IDs.savings || $0.destinationAccountID == IDs.savings) })
        #expect(latest.map(\.date) == latest.map(\.date).sorted(by: >))
        // The withdrawal moved through the account's transfer channel, yet it changed the balance.
        #expect(latest.contains { $0.cardID == IDs.savingsTransfer })
        #expect(!card.categories.isEmpty)
    }
}
