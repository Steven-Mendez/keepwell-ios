import Domain
import DomainSamples
import Foundation
import Testing
@testable import AccountsDomain

@Suite("Cash detail")
struct CashDetailTests {
    private typealias IDs = SampleData.IDs

    private func useCase(_ store: InMemoryStore) -> DefaultGetCashDetailUseCase {
        DefaultGetCashDetailUseCase(accounts: store, cards: store, transactions: store, categories: store, settings: store)
    }

    @Test
    func showsTheBalanceTheWalletPrints() async throws {
        let store = InMemoryStore(sample: .standard)
        let detail = try await useCase(store).execute(accountID: IDs.cash)
        let cash = try #require(try await DefaultGetAccountsOverviewUseCase(
            accounts: store, cards: store, transactions: store, settings: store,
        ).execute().cash.first { $0.id == IDs.cash })
        #expect(detail.balance == cash.balance)
        #expect(detail.principalEquivalent == cash.principalEquivalent)
    }

    @Test
    func latestMovementsAreConfirmedAndNewestFirst() async throws {
        let detail = try await useCase(InMemoryStore(sample: .standard)).execute(accountID: IDs.cash)
        #expect(detail.latestTransactions.count <= CashDetail.latestCount)
        let confirmed = detail.latestTransactions.allSatisfy(\.isConfirmed)
        #expect(confirmed)
        #expect(detail.latestTransactions == detail.latestTransactions.sorted { $0.date > $1.date })
    }

    @Test
    func countsEveryMovementThatDeletingWouldRemove() async throws {
        let store = InMemoryStore(sample: .standard)
        let detail = try await useCase(store).execute(accountID: IDs.cash)
        let touching = await store.fetchTransactions(in: nil).count { TransactionScope.account(IDs.cash).includes($0) }
        #expect(detail.movementCount == touching)
        #expect(touching > 0)
    }

    @Test
    func aBankAccountIsNotCash() async {
        await #expect(throws: DomainError.notFound(IDs.savings)) {
            _ = try await useCase(InMemoryStore(sample: .standard)).execute(accountID: IDs.savings)
        }
    }
}
