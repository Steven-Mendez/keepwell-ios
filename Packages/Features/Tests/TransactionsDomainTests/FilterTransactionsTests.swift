import Domain
import DomainSamples
import Foundation
import Testing
@testable import TransactionsDomain

@Suite("Filtering transactions")
struct FilterTransactionsTests {
    private typealias IDs = SampleData.IDs
    private let filter = DefaultFilterTransactionsUseCase()

    private func list() async throws -> TransactionList {
        let store = InMemoryStore(sample: .standard)
        return try await DefaultGetTransactionListUseCase(
            transactions: store, accounts: store, cards: store, categories: store, settings: store,
        ).execute()
    }

    private func run(_ query: TransactionQuery, on list: TransactionList) -> [Transaction] {
        filter.execute(list.transactions, matching: query) { $0.description }
    }

    @Test
    func anEmptyQueryKeepsEverything() async throws {
        let list = try await list()
        #expect(run(TransactionQuery(), on: list) == list.transactions)
    }

    @Test
    func anAccountKeepsItsMovementsAndTransfersIntoIt() async throws {
        let list = try await list()
        let cash = run(TransactionQuery(scope: .account(IDs.cash)), on: list)
        #expect(!cash.isEmpty)
        #expect(cash.allSatisfy { $0.accountID == IDs.cash || $0.destinationAccountID == IDs.cash })
        #expect(cash.contains { $0.description == "Cardless withdrawal" })
    }

    @Test
    func kindScopeAndSearchCombine() async throws {
        let list = try await list()
        let movies = run(TransactionQuery(kind: .expense, scope: .account(IDs.savings), text: "  MOVIES "), on: list)
        #expect(movies.map(\.description) == ["Movies"])
        // The planned groceries only show under "Planned", and only on their own account.
        #expect(run(TransactionQuery(kind: .expense, scope: .account(IDs.savings), text: "groceries"), on: list).isEmpty)
        #expect(run(TransactionQuery(kind: .planned, scope: .account(IDs.savings), text: "groceries"), on: list).count == 1)
        #expect(run(TransactionQuery(kind: .planned, scope: .account(IDs.cash), text: "groceries"), on: list).isEmpty)
    }

    @Test
    func searchIgnoresAccents() {
        let movement = Transaction(
            date: .now, description: "Café", kind: .expense, categoryID: nil, amount: 3, currency: "USD",
            accountID: UUID(), exchangeRate: .single("USD"),
        )
        #expect(filter.execute([movement], matching: TransactionQuery(text: "cafe")) { $0.description } == [movement])
    }

    @Test
    func pickerListsEachAccountOnceAsItsCard() async throws {
        let options = try await list().scopeOptions
        #expect(options.map(\.account.kind) == [.credit, .credit, .deposit, .deposit, .cash])
        #expect(options.first { $0.id == IDs.savings }?.card?.id == IDs.savingsDebit)
        // A credit card shows as its one plastic.
        #expect(options.first { $0.id == IDs.mastercard }?.card?.id == IDs.mastercardHolder)
        #expect(options.first { $0.id == IDs.cash }?.card == nil)
    }

    @Test
    func anAccountsBalanceIsTheOneItsCardShows() async throws {
        let list = try await list()
        let calendar = Calendar.current
        let account = try #require(list.accounts.first { $0.id == IDs.savings })
        let expected = Balances.balance(of: account, transactions: list.transactions, calendar: calendar)
        #expect(list.balances(in: .account(IDs.savings), calendar: calendar) == expected)
        #expect(list.balances(in: .all, calendar: calendar) == nil)
        #expect(list.account(in: .account(IDs.savings))?.id == IDs.savings)
        // A dual card's two debts become one principal-currency total, converted, never summed raw.
        let debts = try #require(list.balances(in: .account(IDs.mastercard), calendar: calendar))
        let total = try #require(list.balanceTotal(in: .account(IDs.mastercard), calendar: calendar))
        #expect(try total == (NetWorth.total(of: debts, settings: list.settings)))
        #expect(total.currency == list.settings.principal)
    }
}
