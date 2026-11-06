import Foundation
import Testing
@testable import Domain

/// The shared fixture: keepwell-web `tests/domain/forecast.test.ts` builds the same ledger and
/// expects the same numbers, so both platforms forecast alike. Today is Nov 6 2026 (30 days, 24 left).
@Suite("Balance forecast")
struct BalanceForecastTests {
    private let calendar = Fixtures.calendar
    private let now = Fixtures.date(2026, 11, 6)
    private let rate = Fixtures.decimal("36.5")

    private enum IDs {
        static let bank = UUID()
        static let wallet = UUID()
        static let visa = UUID()
        static let mastercard = UUID()
        static let diners = UUID()
    }

    private var settings: CurrencySettings {
        get throws { try CurrencySettings(principal: "USD", second: "NIO", rate: rate) }
    }

    private func account(
        _ id: UUID,
        _ kind: AccountKind,
        _ opening: String,
        _ currency: String,
        cutoff: Int? = nil,
        due: Int? = nil,
    ) throws -> Account {
        let terms = kind == .credit ? try CreditTerms(debtMode: .principal, cutoffDay: cutoff, dueDay: due) : nil
        return Account(
            id: id, name: "\(kind)", kind: kind,
            openingBalances: [Money(Fixtures.decimal(opening), currency)],
            openingDate: Fixtures.date(2026, 7, 1, hour: 0), creditTerms: terms,
        )
    }

    private func movement(
        _ kind: TransactionKind,
        _ amount: String,
        _ currency: String = "USD",
        on date: Date,
        from account: UUID = IDs.bank,
        to destination: UUID? = nil,
        planned: Bool = false,
        rule: UUID? = nil,
    ) throws -> Transaction {
        try Transaction(
            date: date, status: planned ? .planned : .confirmed, description: "Movement", kind: kind,
            categoryID: kind == .transfer ? nil : "other-expense", amount: Fixtures.decimal(amount), currency: currency,
            accountID: account, destinationAccountID: destination,
            exchangeRate: ExchangeRate(principal: "USD", second: "NIO", rate: rate), recurringID: rule,
        )
    }

    private func rule(
        _ kind: TransactionKind,
        _ amount: String,
        _ currency: String = "USD",
        from account: UUID = IDs.bank,
        every frequency: RecurringFrequency = .monthly,
        start: Date,
        next: Date,
        end: Date? = nil,
        paused: Bool = false,
    ) -> RecurringRule {
        RecurringRule(
            name: "Rule", kind: kind, categoryID: kind == .transfer ? nil : "other-expense",
            amount: Fixtures.decimal(amount), currency: currency, accountID: account,
            destinationAccountID: kind == .transfer ? IDs.wallet : nil, frequency: frequency,
            startDate: start, nextDate: next, endDate: end, isPaused: paused,
        )
    }

    private func ledger() throws -> (accounts: [Account], transactions: [Transaction], rules: [RecurringRule]) {
        let accounts = try [
            account(IDs.bank, .deposit, "5000", "USD"),
            account(IDs.wallet, .cash, "3650", "NIO"),
            account(IDs.visa, .credit, "0", "USD", cutoff: 20, due: 10),
            account(IDs.mastercard, .credit, "0", "USD", cutoff: 25, due: 3),
            account(IDs.diners, .credit, "0", "USD"),
        ]
        let transactions = try [
            // History: July is outside the three complete months; rule charges and cards don't count.
            movement(.expense, "1000", on: Fixtures.date(2026, 7, 15)),
            movement(.expense, "300", on: Fixtures.date(2026, 8, 10)),
            movement(.expense, "580", on: Fixtures.date(2026, 9, 10)),
            movement(.expense, "730", "NIO", on: Fixtures.date(2026, 9, 12), from: IDs.wallet),
            movement(.expense, "900", on: Fixtures.date(2026, 10, 10)),
            movement(.expense, "50", on: Fixtures.date(2026, 10, 1), rule: UUID()),
            movement(.expense, "400", on: Fixtures.date(2026, 10, 5), from: IDs.visa),
            movement(.expense, "100", on: Fixtures.date(2026, 10, 25), from: IDs.visa),
            movement(.expense, "200", on: Fixtures.date(2026, 10, 26), from: IDs.mastercard),
            movement(.expense, "60", on: Fixtures.date(2026, 10, 8), from: IDs.diners),
            movement(.income, "2000", on: Fixtures.date(2026, 10, 30)),
            movement(.transfer, "150", on: Fixtures.date(2026, 11, 2), to: IDs.visa),
            movement(.expense, "70", on: Fixtures.date(2026, 11, 3)),
            // Drafts: only today through Nov 30, on bank and cash, and not transfers.
            movement(.expense, "120", on: Fixtures.date(2026, 11, 20), planned: true),
            movement(.expense, "1825", "NIO", on: Fixtures.date(2026, 11, 25), from: IDs.wallet, planned: true),
            movement(.income, "300", on: Fixtures.date(2026, 11, 15), planned: true),
            movement(.expense, "999", on: Fixtures.date(2026, 12, 2), planned: true),
            movement(.expense, "77", on: Fixtures.date(2026, 11, 1), planned: true),
            movement(.expense, "40", on: Fixtures.date(2026, 11, 18), from: IDs.visa, planned: true),
            movement(.transfer, "100", on: Fixtures.date(2026, 11, 21), to: IDs.wallet, planned: true),
        ]
        let rules = [
            rule(.expense, "500", start: Fixtures.date(2026, 1, 28), next: Fixtures.date(2026, 11, 28)),
            rule(.expense, "10", every: .weekly, start: Fixtures.date(2026, 10, 2), next: Fixtures.date(2026, 11, 13)),
            rule(.income, "200", start: Fixtures.date(2026, 6, 30), next: Fixtures.date(2026, 11, 30)),
            rule(.expense, "365", "NIO", from: IDs.wallet, start: Fixtures.date(2026, 1, 9), next: Fixtures.date(2026, 11, 9)),
            rule(.expense, "15", from: IDs.visa, start: Fixtures.date(2026, 1, 12), next: Fixtures.date(2026, 11, 12)),
            rule(.expense, "1000", start: Fixtures.date(2026, 1, 20), next: Fixtures.date(2026, 11, 20), paused: true),
            rule(.expense, "1000", start: Fixtures.date(2026, 1, 8), next: Fixtures.date(2026, 11, 8), end: Fixtures.date(2026, 10, 31)),
            rule(.transfer, "100", start: Fixtures.date(2026, 1, 15), next: Fixtures.date(2026, 11, 15)),
        ]
        return (accounts, transactions, rules)
    }

    @Test
    func forecastsTheSharedFixture() throws {
        let ledger = try ledger()
        let forecast = try BalanceForecast(
            accounts: ledger.accounts, transactions: ledger.transactions, rules: ledger.rules,
            settings: settings, now: now, calendar: calendar,
        )
        #expect(forecast.currency == "USD")
        #expect(forecast.availableToday == 4030)
        #expect(forecast.draftIncome == 300)
        #expect(forecast.draftExpenses == 170)
        #expect(forecast.recurringIncome == 200)
        #expect(forecast.recurringExpenses == 540)
        #expect(forecast.plannedIncome == 500)
        #expect(forecast.plannedExpenses == 710)
        #expect(forecast.cardPayments == 250)
        #expect(forecast.usualSpending == 480)
        #expect(forecast.total == 3090)
    }

    @Test
    func theStatementIsWhatClosedLessWhatWasPaidSince() throws {
        let ledger = try ledger()
        let visa = try #require(ledger.accounts.first { $0.id == IDs.visa })
        let diners = try #require(ledger.accounts.first { $0.id == IDs.diners })
        let due = Fixtures.date(2026, 11, 10, hour: 0)
        #expect(try CardStatement.amountDue(
            on: due,
            account: visa,
            transactions: ledger.transactions,
            settings: settings,
            calendar: calendar,
        ) == 250)
        // Without a cutoff day the whole debt is due.
        #expect(try CardStatement.amountDue(
            on: due,
            account: diners,
            transactions: ledger.transactions,
            settings: settings,
            calendar: calendar,
        ) == 60)
    }

    @Test
    func statementCutoffIsTheLastOneBeforeTheDueDay() {
        #expect(BillingCycle.statementCutoff(before: Fixtures.date(2026, 11, 10), cutoffDay: 20, calendar: calendar)
            == calendar.startOfDay(for: Fixtures.date(2026, 10, 20)))
        #expect(BillingCycle.statementCutoff(before: Fixtures.date(2026, 11, 25), cutoffDay: 5, calendar: calendar)
            == calendar.startOfDay(for: Fixtures.date(2026, 11, 5)))
    }

    @Test
    func usualSpendingAveragesOnlyMonthsWithSpending() throws {
        let transactions = try [movement(.expense, "600", on: Fixtures.date(2026, 10, 10))]
        let forecast = try BalanceForecast(
            accounts: [account(IDs.bank, .deposit, "0", "USD")], transactions: transactions, rules: [],
            settings: settings, now: now, calendar: calendar,
        )
        #expect(forecast.usualSpending == 480)
        #expect(forecast.total == -1080)
    }
}
