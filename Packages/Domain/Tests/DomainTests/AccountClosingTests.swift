import DomainSamples
import Foundation
import Testing
@testable import Domain

/// Closing an account keeps its history (T25, ports keepwell-web `tests/domain/close-account.test.ts`).
@Suite("Closing an account")
struct AccountClosingTests {
    private typealias IDs = SampleData.IDs
    private let sample = SampleData.standard
    private let calendar = Fixtures.calendar
    private var now: Date { SampleData.defaultReferenceDate }

    private func closing(_ store: InMemoryStore) -> DefaultAccountClosingUseCase {
        DefaultAccountClosingUseCase(
            accounts: store, cards: store, transactions: store, recurringRules: store, settings: store,
            calendar: calendar, now: { [now] in now },
        )
    }

    private func plan(_ id: UUID, in store: InMemoryStore) async throws -> ClosingPlan {
        let use: any GetClosingPlanUseCase = closing(store)
        return try await use.execute(accountID: id)
    }

    private func reopen(_ id: UUID, in store: InMemoryStore) async throws {
        let use: any ReopenAccountUseCase = closing(store)
        try await use.execute(accountID: id)
    }

    private func balances(of id: UUID, in store: InMemoryStore) async throws -> [Money] {
        let account = try #require(await store.fetchAccounts().first { $0.id == id })
        return await Balances.balance(of: account, transactions: store.fetchTransactions(in: nil), calendar: calendar)
    }

    private let emptyWallet = Account(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000A0E0") ?? UUID(),
        name: "Old wallet", kind: .cash, openingBalances: [Money(0, "USD")], openingDate: .distantPast,
    )

    private func store(with extra: [Account] = []) -> InMemoryStore {
        InMemoryStore(
            accounts: sample.accounts + extra, cards: sample.cards, transactions: sample.transactions,
            categories: sample.categories, settings: sample.settings, recurringRules: sample.recurringRules,
        )
    }

    @Test
    func anEmptyAccountClosesAtOnceAndClosingAgainDoesNothing() async throws {
        let store = store(with: [emptyWallet])
        let closed = try await closing(store).execute(accountID: emptyWallet.id, transferTo: nil, description: "Closing transfer")
        #expect(closed.closedAt == now)
        let again = try await DefaultAccountClosingUseCase(
            accounts: store, cards: store, transactions: store, recurringRules: store, settings: store,
            calendar: calendar, now: { [now] in now.addingTimeInterval(86400) },
        ).execute(accountID: emptyWallet.id, transferTo: nil, description: "Closing transfer")
        #expect(again.closedAt == now)
    }

    @Test
    func moneyLeftWithoutADestinationIsRefusedAndNothingChanges() async throws {
        let store = store()
        let before = await store.fetchTransactions(in: nil)
        await #expect(throws: DomainError.accountNotEmpty(IDs.savings)) {
            try await closing(store).execute(accountID: IDs.savings, transferTo: nil, description: "Closing transfer")
        }
        #expect(await store.fetchAccounts().first { $0.id == IDs.savings }?.isOpen == true)
        #expect(await store.fetchTransactions(in: nil) == before)
    }

    @Test
    func theBalanceOnlyMovesToAnotherOpenAccountWithItsCurrency() async throws {
        let store = store()
        // The wallet holds córdobas only; savings is in dollars.
        await #expect(throws: DomainError.invalidTransferDestination) {
            try await closing(store).execute(accountID: IDs.savings, transferTo: IDs.cash, description: "Closing transfer")
        }
        try await closing(store).execute(accountID: IDs.payroll, transferTo: IDs.savings, description: "Closing transfer")
        await #expect(throws: DomainError.invalidTransferDestination) {
            try await closing(store).execute(accountID: IDs.savings, transferTo: IDs.payroll, description: "Closing transfer")
        }
    }

    @Test
    func movingTheBalanceOutKeepsEveryTotalAndSummary() async throws {
        let store = store()
        let settings = sample.settings.currencies
        let month = YearMonth(containing: now, calendar: calendar)
        func totals() async throws -> (Money, [NetWorthHistory.Point], MonthlySummary) {
            let accounts = await store.fetchAccounts()
            let movements = await store.fetchTransactions(in: nil)
            let all = accounts.flatMap { Balances.balance(of: $0, transactions: movements, calendar: calendar) }
            return try (
                NetWorth.total(of: all, settings: settings),
                NetWorthHistory.points(accounts: accounts, transactions: movements, settings: settings, now: now, calendar: calendar),
                MonthlySummary(month: month, transactions: movements, currency: "USD", calendar: calendar),
            )
        }
        let before = try await totals()
        let saved = try await balances(of: IDs.savings, in: store)

        try await closing(store).execute(accountID: IDs.savings, transferTo: IDs.payroll, description: "Transferencia de cierre")

        let transfers = await store.fetchTransactions(in: nil).filter { $0.description == "Transferencia de cierre" }
        #expect(transfers.count == 1)
        #expect(transfers.first?.accountID == IDs.savings)
        #expect(transfers.first?.cardID == IDs.savingsTransfer)
        #expect(transfers.first?.destinationAccountID == IDs.payroll)
        #expect(transfers.first?.amount == saved.first?.amount)
        #expect(try await balances(of: IDs.savings, in: store).allSatisfy { $0.amount == 0 })
        let after = try await totals()
        #expect(after.0 == before.0)
        #expect(after.1 == before.1)
        #expect(after.2 == before.2)
        #expect(await !store.fetchAccounts().open.contains { $0.id == IDs.savings })
    }

    @Test
    func aDualCardIsPaidOffWithOneTransferPerCurrency() async throws {
        let dual = Account(
            name: "Dual savings", kind: .deposit, openingBalances: [Money(5000, "USD"), Money(90000, "NIO")], openingDate: .distantPast,
        )
        let store = store(with: [dual])
        let found = try await plan(IDs.mastercard, in: store)
        #expect(Set(found.balances.map(\.currency)) == ["USD", "NIO"])
        #expect(found.destinations.map(\.id) == [dual.id])

        try await closing(store).execute(accountID: IDs.mastercard, transferTo: dual.id, description: "Closing transfer")

        let transfers = await store.fetchTransactions(in: nil).filter { $0.description == "Closing transfer" }
        #expect(transfers.count == 2)
        #expect(transfers.allSatisfy { $0.accountID == dual.id && $0.destinationAccountID == IDs.mastercard })
        #expect(try await balances(of: IDs.mastercard, in: store).allSatisfy { $0.amount == 0 })
    }

    @Test
    func rulesFromOrToTheAccountArePausedAndTheirDraftsDeleted() async throws {
        let store = store(with: [emptyWallet])
        let rent = RecurringRule(
            name: "Rent", kind: .expense, categoryID: "housing", amount: 300, currency: "USD", accountID: emptyWallet.id,
            frequency: .monthly, startDate: now, nextDate: now,
        )
        await store.save(rent)
        let draft = Transaction(
            date: now, status: .planned, description: "Rent", kind: .expense, categoryID: "housing", amount: 300, currency: "USD",
            accountID: emptyWallet.id, exchangeRate: Fixtures.usdNio, recurringID: rent.id,
        )
        await store.save(draft)
        let found = try await plan(emptyWallet.id, in: store)
        #expect(found.rulesToPause.map(\.id) == [rent.id])
        #expect(found.draftsToDelete.map(\.id) == [draft.id])

        try await closing(store).execute(accountID: emptyWallet.id, transferTo: nil, description: "Closing transfer")

        let rules = await store.fetchRecurringRules()
        #expect(rules.first { $0.id == rent.id }?.isPaused == true)
        #expect(rules.first { $0.id == IDs.rentRule }?.isPaused == false)
        #expect(await !store.fetchTransactions(in: nil).contains { $0.id == draft.id })
    }

    @Test
    func reopeningClearsTheClosingAndKeepsEverythingElse() async throws {
        let store = store()
        let use = closing(store)
        try await use.execute(accountID: IDs.savings, transferTo: IDs.payroll, description: "Closing transfer")
        let movements = await store.fetchTransactions(in: nil)
        try await reopen(IDs.savings, in: store)
        #expect(await store.fetchAccounts().first { $0.id == IDs.savings }?.closedAt == nil)
        #expect(await store.fetchTransactions(in: nil) == movements)
    }

    @Test
    func aClosedAccountTakesNoNewMovementButOldOnesKeepEditingTheirCategory() throws {
        let closed = Account(name: "Old", kind: .cash, openingBalances: [Money(0, "USD")], openingDate: .distantPast, closedAt: now)
        let open = Account(name: "New", kind: .cash, openingBalances: [Money(0, "USD")], openingDate: .distantPast)
        let accounts = [closed, open]
        let old = Fixtures.transaction(amount: "5", account: closed.id, category: "restaurants")
        #expect(throws: DomainError.accountClosed(closed.id)) {
            try Transaction.checkClosedAccounts(Fixtures.transaction(amount: "5", account: closed.id), accounts: accounts)
        }
        #expect(throws: DomainError.accountClosed(closed.id)) {
            try Transaction.checkClosedAccounts(
                Fixtures.transaction(.transfer, amount: "5", account: open.id, destination: closed.id), accounts: accounts,
            )
        }
        let recategorized = Transaction(
            id: old.id, date: old.date, description: "Cinema", kind: .expense, categoryID: "leisure", amount: old.amount,
            currency: old.currency, accountID: old.accountID, exchangeRate: old.exchangeRate, note: "with Ana",
        )
        try Transaction.checkClosedAccounts(recategorized, existing: old, accounts: accounts)
        #expect(throws: DomainError.accountClosed(closed.id)) {
            try Transaction.checkClosedAccounts(old.with(date: now), existing: old, accounts: accounts)
        }
    }
}
