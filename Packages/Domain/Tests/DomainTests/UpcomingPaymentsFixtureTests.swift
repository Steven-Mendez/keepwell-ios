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
            /// Absent in the cases written before personal debts had a due date: none.
            let personalDebts: [DebtRow]?
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
            let closedAt: String?
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
            let destinationAccountId: UUID?
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

        struct RepaymentRow: Decodable {
            let id: UUID
            let amount: String
            let date: String
        }

        struct DebtRow: Decodable {
            let id: UUID
            let person: String
            let direction: DebtDirection
            let amount: MoneyRow
            let date: String
            let repayments: [RepaymentRow]
            let settledAt: String?
            let dueDate: String?
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
            personalDebts: (rows.personalDebts ?? []).map(debt),
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
            closedAt: row.closedAt.map(date),
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
            destinationAccountID: row.destinationAccountId,
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

    private static func debt(_ row: File.DebtRow) throws -> PersonalDebt {
        try PersonalDebt(
            id: row.id,
            person: row.person,
            direction: row.direction,
            amount: money(row.amount),
            date: date(row.date),
            repayments: row.repayments.map { try DebtRepayment(id: $0.id, amount: Fixtures.decimal($0.amount), date: date($0.date)) },
            settledAt: row.settledAt.map(date),
            dueDate: row.dueDate.map(date),
        )
    }
}
