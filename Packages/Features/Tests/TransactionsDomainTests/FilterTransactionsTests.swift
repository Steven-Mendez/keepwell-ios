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

/// The list's amount range and origin filters, mirrored in the web's `transaction-filters.test.ts`.
@Suite("Filtering by amount and origin")
struct AmountAndOriginFilterTests {
    private let filter = DefaultFilterTransactionsUseCase()
    private let rate = (try? ExchangeRate(principal: "USD", second: "NIO", rate: Decimal(string: "36.6243") ?? 1)) ?? .single("USD")

    private func movement(
        _ amount: Decimal,
        _ currency: String = "USD",
        kind: TransactionKind = .expense,
        status: TransactionStatus = .confirmed,
        actualDebited: Decimal? = nil,
        recurringID: UUID? = nil,
        description: String = "x",
    ) -> Transaction {
        Transaction(
            date: SampleData.defaultReferenceDate, status: status, description: description, kind: kind,
            categoryID: kind == .transfer ? nil : "other-expense", amount: amount, currency: currency, accountID: UUID(),
            destinationAccountID: kind == .transfer ? UUID() : nil, actualDebitedPrincipal: actualDebited,
            exchangeRate: rate, recurringID: recurringID,
        )
    }

    private func rule(_ id: UUID, subscription: Bool = false, paused: Bool = false) -> RecurringRule {
        RecurringRule(
            id: id, name: "Netflix", kind: .expense, categoryID: "subscriptions", amount: 15, currency: "USD",
            accountID: UUID(), frequency: .monthly, startDate: SampleData.defaultReferenceDate,
            isSubscription: subscription, isPaused: paused,
        )
    }

    @Test
    func boundsAreInclusive() {
        let hundred = movement(100)
        #expect(AmountRange(min: 100).contains(hundred, principal: "USD"))
        #expect(AmountRange(max: 100).contains(hundred, principal: "USD"))
        #expect(AmountRange(min: 100, max: 100).contains(hundred, principal: "USD"))
        #expect(!AmountRange(min: Decimal(string: "100.01")).contains(hundred, principal: "USD"))
        #expect(!AmountRange(max: Decimal(string: "99.99")).contains(hundred, principal: "USD"))
    }

    @Test
    func theAmountIsComparedRoundedToCentsAsShown() throws {
        #expect(try AmountRange(min: 100).contains(movement(#require(Decimal(string: "99.996"))), principal: "USD"))
        #expect(try !AmountRange(min: 100).contains(movement(#require(Decimal(string: "99.994"))), principal: "USD"))
    }

    @Test
    func aSecondCurrencyMovementIsReadInThePrincipalAtItsOwnRate() throws {
        // NIO 3,662.43 at 36.6243 is USD 100.
        let cordobas = try movement(#require(Decimal(string: "3662.43")), "NIO")
        #expect(AmountRange(min: 100).contains(cordobas, principal: "USD"))
        #expect(!AmountRange(max: Decimal(string: "99.99")).contains(cordobas, principal: "USD"))
        // The bank's real debit wins over the rate.
        let debited = try movement(#require(Decimal(string: "3662.43")), "NIO", actualDebited: 101)
        #expect(AmountRange(min: 101, max: 101).contains(debited, principal: "USD"))
    }

    @Test
    func transfersAreFilteredByTheirAmount() {
        #expect(AmountRange(min: 400, max: 500).contains(movement(500, kind: .transfer), principal: "USD"))
    }

    @Test
    func aMinimumAboveTheMaximumIsAProblemAndMatchesNothing() {
        #expect(AmountRange(min: 500, max: 100).problem == .minAboveMax)
        #expect(AmountRange(min: 100, max: 100).problem == nil)
        #expect(AmountRange(min: 100).problem == nil)
        #expect(!AmountRange(min: 500, max: 100).contains(movement(100), principal: "USD"))
    }

    @Test
    func originsMatchByRuleAndBySubscriptionToday() {
        let rent = UUID(), netflix = UUID(), spotify = UUID(), gone = UUID()
        let rules = [rule(rent), rule(netflix, subscription: true), rule(spotify, subscription: true, paused: true)]
        // A rule matches its movements by id, even once deleted.
        #expect(TransactionOrigin.rule(rent).matches(movement(15, recurringID: rent), rules: rules))
        #expect(!TransactionOrigin.rule(rent).matches(movement(15, recurringID: netflix), rules: rules))
        #expect(TransactionOrigin.rule(gone).matches(movement(15, recurringID: gone), rules: rules))
        // Subscriptions by the rule as it is today, paused or not; a deleted one can't say.
        #expect(TransactionOrigin.subscriptions.matches(movement(15, recurringID: netflix), rules: rules))
        #expect(TransactionOrigin.subscriptions.matches(movement(15, recurringID: spotify), rules: rules))
        #expect(!TransactionOrigin.subscriptions.matches(movement(15, recurringID: rent), rules: rules))
        #expect(!TransactionOrigin.subscriptions.matches(movement(15, recurringID: gone), rules: rules))
        // A movement logged by hand matches neither.
        #expect(!TransactionOrigin.subscriptions.matches(movement(15), rules: rules))
        #expect(!TransactionOrigin.rule(rent).matches(movement(15), rules: rules))
        #expect(TransactionOrigin.any.matches(movement(15), rules: rules))
    }

    @Test
    func theQueryNarrowsByAmountAndOriginOnlyWithAContext() {
        let netflix = UUID()
        let small = movement(15, recurringID: netflix, description: "small")
        let big = movement(250, description: "big")
        let draft = movement(120, status: .planned, description: "draft")
        let all = [small, big, draft]
        let context = TransactionQueryContext(principal: "USD", rules: [rule(netflix, subscription: true)])
        func names(_ query: TransactionQuery, _ context: TransactionQueryContext?) -> [String] {
            filter.execute(all, matching: query, context: context) { $0.description }.map(\.description)
        }
        // Without amount or origin the result is today's.
        #expect(names(TransactionQuery(), nil) == ["small", "big", "draft"])
        #expect(names(TransactionQuery(), context) == ["small", "big", "draft"])
        #expect(names(TransactionQuery(kind: .planned), context) == ["draft"])
        #expect(names(TransactionQuery(amount: AmountRange(min: 100)), context) == ["big", "draft"])
        #expect(names(TransactionQuery(kind: .expense, amount: AmountRange(min: 100)), context) == ["big"])
        #expect(names(TransactionQuery(origin: .subscriptions), context) == ["small"])
        #expect(names(TransactionQuery(amount: AmountRange(min: 20), origin: .rule(netflix)), context).isEmpty)
        #expect(names(TransactionQuery(amount: AmountRange(min: 100), origin: .subscriptions), nil) == ["small", "big", "draft"])
    }
}
