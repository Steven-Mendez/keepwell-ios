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

extension FilterTransactionsTests {
    @Test
    func aHashSearchKeepsOnlyThatTagAndTotalsItInThePrincipalCurrency() throws {
        let rate = try ExchangeRate(principal: "USD", second: "NIO", rate: 36)
        func movement(
            _ kind: TransactionKind,
            _ amount: Decimal,
            _ currency: String,
            tags: [String],
            status: TransactionStatus = .confirmed,
        ) -> Transaction {
            Transaction(
                date: SampleData.defaultReferenceDate, status: status, description: "x", kind: kind,
                categoryID: kind == .income ? "salary" : "travel", amount: amount, currency: currency,
                accountID: IDs.cash, exchangeRate: rate, tags: tags,
            )
        }
        let movements = [
            movement(.expense, 100, "USD", tags: ["boda"]),
            movement(.expense, 360, "NIO", tags: ["viaje", "boda"]),
            movement(.income, 50, "USD", tags: ["boda"]),
            movement(.expense, 999, "USD", tags: ["boda"], status: .planned),
            movement(.expense, 7, "USD", tags: ["viaje"]),
        ]
        let found = filter.execute(movements, matching: TransactionQuery(text: " #Boda ")) { $0.description }
        #expect(found.count == 4)
        let totals = TagTotals(tag: "boda", transactions: found, currency: "USD")
        #expect(totals.expense == 110)
        #expect(totals.income == 50)
        #expect(TransactionQuery(text: "boda").tag == nil)
    }
}
