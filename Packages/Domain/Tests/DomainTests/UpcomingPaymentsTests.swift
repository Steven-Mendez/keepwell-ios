import Foundation
import Testing
@testable import Domain

/// The cases keepwell-web and keepwell-api run too (`upcoming.json`): the same ledger must give the
/// same ids, statuses and order on every platform.
@Suite("Shared upcoming fixtures")
struct UpcomingPaymentsFixtureTests {
    /// The entities in their sync shape (camelCase, decimal text, ISO dates), read by hand so the
    /// file stays a verbatim copy of the web's.
    private struct File: Decodable {
        struct Case: Decodable {
            let name: String
            let now: String
            let timeZone: String
            let ledger: Ledger
            let windows: [Window]
        }

        struct Window: Decodable {
            let days: Int
            let expected: [Expected]
        }

        struct Expected: Decodable, Equatable {
            let id: String
            let status: String
        }

        struct Ledger: Decodable {
            let currencies: Currencies
            let accounts: [AccountRow]
            let transactions: [TransactionRow]
            let recurringRules: [RuleRow]
            let loans: [LoanRow]
        }

        struct Currencies: Decodable {
            let principal: String
            let second: String?
            let rate: String
        }

        struct MoneyRow: Decodable {
            let amount: String
            let currency: String
        }

        struct Terms: Decodable {
            let debtMode: DebtMode
            let cutoffDay: Int?
            let dueDay: Int?
        }

        struct AccountRow: Decodable {
            let id: UUID
            let name: String
            let kind: AccountKind
            let openingBalances: [MoneyRow]
            let openingDate: String
            let creditTerms: Terms?
        }

        struct Rate: Decodable {
            let principal: String
            let second: String
            let rate: String
        }

        struct TransactionRow: Decodable {
            let id: UUID
            let date: String
            let status: TransactionStatus
            let description: String
            let kind: TransactionKind
            let amount: String
            let currency: String
            let accountId: UUID
            let exchangeRate: Rate
            let recurringId: UUID?
        }

        struct RuleRow: Decodable {
            let id: UUID
            let name: String
            let kind: TransactionKind
            let amount: String
            let currency: String
            let accountId: UUID
            let frequency: RecurringFrequency
            let interval: Int
            let startDate: String
            let nextDate: String
            let endDate: String?
            let isSubscription: Bool
            let autoConfirm: Bool
            let isPaused: Bool
        }

        struct PaymentRow: Decodable {
            let number: Int
            let paidAt: String
        }

        struct LoanRow: Decodable {
            let id: UUID
            let name: String
            let borrowed: MoneyRow
            let installmentAmount: String
            let installmentCount: Int
            let frequency: LoanFrequency
            let firstDueDate: String
            let payments: [PaymentRow]
        }

        let cases: [Case]
    }

    private static func date(_ text: String) throws -> Date {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try #require(parser.date(from: text))
    }

    private static func money(_ row: File.MoneyRow) -> Money {
        Money(Fixtures.decimal(row.amount), row.currency)
    }

    @Test
    func everyWindowMatchesTheWeb() throws {
        let url = try #require(Bundle.module.url(forResource: "upcoming", withExtension: "json", subdirectory: "Fixtures"))
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        for entry in file.cases {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: entry.timeZone))
            let ledger = try Self.ledger(entry.ledger)
            for window in entry.windows {
                let payments = try UpcomingPayments.compute(ledger, on: Self.date(entry.now), days: window.days, calendar: calendar)
                let got = payments.map { File.Expected(id: $0.id, status: $0.status.rawValue) }
                #expect(got == window.expected, "\(entry.name), \(window.days) days")
            }
        }
    }

    private static func ledger(_ rows: File.Ledger) throws -> UpcomingPayments.Ledger {
        try UpcomingPayments.Ledger(
            transactions: rows.transactions.map(transaction),
            rules: rows.recurringRules.map(rule),
            accounts: rows.accounts.map(account),
            loans: rows.loans.map(loan),
            settings: CurrencySettings(
                principal: rows.currencies.principal,
                second: rows.currencies.second,
                rate: Fixtures.decimal(rows.currencies.rate),
            ),
        )
    }

    private static func account(_ row: File.AccountRow) throws -> Account {
        let terms = try row.creditTerms.map { terms throws(DomainError) in
            try CreditTerms(debtMode: terms.debtMode, cutoffDay: terms.cutoffDay, dueDay: terms.dueDay)
        }
        return try Account(
            id: row.id,
            name: row.name,
            kind: row.kind,
            openingBalances: row.openingBalances.map(money),
            openingDate: date(row.openingDate),
            creditTerms: terms,
        )
    }

    private static func transaction(_ row: File.TransactionRow) throws -> Transaction {
        let rate = row.exchangeRate
        return try Transaction(
            id: row.id,
            date: date(row.date),
            status: row.status,
            description: row.description,
            kind: row.kind,
            categoryID: nil,
            amount: Fixtures.decimal(row.amount),
            currency: row.currency,
            accountID: row.accountId,
            exchangeRate: rate.principal == rate.second
                ? .single(rate.principal)
                : ExchangeRate(principal: rate.principal, second: rate.second, rate: Fixtures.decimal(rate.rate)),
            recurringID: row.recurringId,
        )
    }

    private static func rule(_ row: File.RuleRow) throws -> RecurringRule {
        try RecurringRule(
            id: row.id,
            name: row.name,
            kind: row.kind,
            categoryID: nil,
            amount: Fixtures.decimal(row.amount),
            currency: row.currency,
            accountID: row.accountId,
            frequency: row.frequency,
            interval: row.interval,
            startDate: date(row.startDate),
            nextDate: date(row.nextDate),
            endDate: row.endDate.map(date),
            isSubscription: row.isSubscription,
            autoConfirm: row.autoConfirm,
            isPaused: row.isPaused,
        )
    }

    private static func loan(_ row: File.LoanRow) throws -> Loan {
        try Loan(
            id: row.id,
            name: row.name,
            borrowed: money(row.borrowed),
            installmentAmount: Fixtures.decimal(row.installmentAmount),
            installmentCount: row.installmentCount,
            frequency: row.frequency,
            firstDueDate: date(row.firstDueDate),
            payments: row.payments.map { try LoanPayment(number: $0.number, paidAt: date($0.paidAt)) },
        )
    }
}

/// Same cases as the web's `upcomingPayments` suite (`tests/domain/upcoming-payments.test.ts`).
@Suite("Upcoming payments")
struct UpcomingPaymentsTests {
    private let calendar = Fixtures.calendar
    private let now = Fixtures.date(2026, 11, 12, hour: 15)
    private let loanID = UUID()
    private let bank = UUID()

    private func compute(
        transactions: [Transaction] = [],
        rules: [RecurringRule] = [],
        accounts: [Account] = [],
        loans: [Loan] = [],
        on date: Date? = nil,
        days: Int,
    ) -> [UpcomingPayment] {
        UpcomingPayments.compute(
            UpcomingPayments.Ledger(transactions: transactions, rules: rules, accounts: accounts, loans: loans),
            on: date ?? now,
            days: days,
            calendar: calendar,
        )
    }

    private func loan(frequency: LoanFrequency = .monthly, count: Int = 12, first: Date) -> Loan {
        Loan(
            id: loanID, name: "Motorbike", borrowed: Money(1200, "USD"), installmentAmount: 100,
            installmentCount: count, frequency: frequency, firstDueDate: first,
        )
    }

    private func rule(start: Date, next: Date, end: Date? = nil, paused: Bool = false) -> RecurringRule {
        RecurringRule(
            name: "Gym", kind: .expense, categoryID: nil, amount: 25, currency: "USD", accountID: bank,
            frequency: .monthly, startDate: start, nextDate: next, endDate: end, isPaused: paused,
        )
    }

    @Test
    func everyOverdueInstallmentHasItsOwnRowAndDays() {
        let payments = compute(loans: [loan(first: Fixtures.date(2026, 9, 10, hour: 0))], days: 0)
        let id = loanID.uuidString.lowercased()
        #expect(payments.map(\.id) == ["installment:\(id):1", "installment:\(id):2", "installment:\(id):3"])
        #expect(payments.map(\.daysFromToday) == [-63, -33, -2])
        #expect(payments.allSatisfy { $0.status == .overdue })
        #expect(payments.first?.kind == .installment(loanID: loanID, number: 1, count: 12))
        #expect(payments.first?.amount == Money(100, "USD"))
    }

    @Test
    func aWeeklyLoanHasSeveralInstallmentsInTheWindow() {
        let weekly = loan(frequency: .weekly, count: 4, first: Fixtures.date(2026, 11, 13, hour: 0))
        #expect(compute(loans: [weekly], days: 14).count == 2)
    }

    @Test
    func aDraftDatedAheadIsUpcomingAndNoneAfterTheWindow() {
        let ahead = Fixtures.transaction(amount: "10", status: .planned, date: Fixtures.date(2026, 11, 15))
        let far = Fixtures.transaction(amount: "10", status: .planned, date: Fixtures.date(2026, 11, 30))
        let payments = compute(transactions: [ahead, far], days: 7)
        #expect(payments.map(\.id) == ["draft:\(ahead.id.uuidString.lowercased())"])
        #expect(payments.map(\.status) == [.upcoming])
    }

    @Test
    func todaysOccurrenceIsTodayAndEndedOrPausedRulesHaveNone() {
        let start = Fixtures.date(2026, 1, 12)
        let today = Fixtures.date(2026, 11, 12)
        let active = rule(start: start, next: today)
        let ended = rule(start: start, next: today, end: Fixtures.date(2026, 11, 1))
        let paused = rule(start: start, next: today, paused: true)
        let payments = compute(rules: [active, ended, paused], days: 3)
        #expect(payments.map(\.id) == ["recurring:\(active.id.uuidString.lowercased()):2026-11-12"])
        #expect(payments.map(\.status) == [.today])
    }

    @Test
    func aCardWithNothingToPayIsLeftOut() throws {
        let terms = { (day: Int) throws(DomainError) in try CreditTerms(debtMode: .principal, dueDay: day) }
        let owes = try Account(
            name: "Visa", kind: .credit, openingBalances: [Money(0, "USD")], openingDate: Fixtures.date(2026, 1, 1),
            creditTerms: terms(14),
        )
        let paid = try Account(
            name: "Amex", kind: .credit, openingBalances: [Money(0, "USD")], openingDate: Fixtures.date(2026, 1, 1),
            creditTerms: terms(13),
        )
        let charge = Fixtures.transaction(amount: "80", account: owes.id, date: Fixtures.date(2026, 11, 2), rate: .single("USD"))
        let payments = compute(transactions: [charge], accounts: [owes, paid], days: 7)
        #expect(payments.map(\.id) == ["card:\(owes.id.uuidString.lowercased()):2026-11-14"])
        #expect(payments.first?.amount == Money(80, "USD"))
    }

    @Test
    func ordersByDayThenKindThenIDBytes() {
        let day = now
        let draft = Fixtures.transaction(amount: "1", status: .planned, date: day)
        let item = { (id: String, kind: UpcomingPayment.Kind, days: Int) in
            UpcomingPayment(id: id, kind: kind, date: day, amount: Money(1, "USD"), daysFromToday: days)
        }
        let recurring = UpcomingPayment.Kind.recurring(rule(start: day, next: day))
        let sorted = [
            item("recurring:b", recurring, 0),
            item("debt:a", .debt(debtID: UUID(), person: "Ana", direction: .iOwe), 0),
            item("card:a", .card(accountID: bank, dueDay: 1), 0),
            item("draft:b", .draft(draft), 0),
            item("draft:B", .draft(draft), 0),
            item("installment:a", .installment(loanID: loanID, number: 1, count: 1), 0),
            item("recurring:a", recurring, -1),
        ].sorted(by: UpcomingPayment.precedes)
        #expect(sorted.map(\.id) == ["recurring:a", "draft:B", "draft:b", "installment:a", "card:a", "recurring:b", "debt:a"])
    }

    @Test
    func countsCalendarDaysInTheCalendarsZone() {
        // 11pm in Managua on the 12th is already the 13th in UTC: today stays the 12th.
        let late = Fixtures.date(2026, 11, 12, hour: 23)
        let gym = rule(start: Fixtures.date(2026, 1, 13), next: Fixtures.date(2026, 11, 13))
        let payments = compute(rules: [gym], on: late, days: 1)
        #expect(payments.map(\.daysFromToday) == [1])
        #expect(payments.map(\.status) == [.upcoming])
    }
}
