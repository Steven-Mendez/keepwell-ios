import Domain
import Foundation
import TransactionsDomain

/// Returns `transactions` for any period on purpose, so tests prove the use cases apply the month
/// and status rules themselves instead of trusting the repository's filtering.
actor MockTransactionRepository: TransactionRepository {
    private let transactions: [Transaction]
    private let error: DomainError?
    private(set) var requestedPeriods: [DateInterval?] = []
    private(set) var added: [Transaction] = []
    private(set) var deletedIDs: [UUID] = []

    init(transactions: [Transaction] = [], error: DomainError? = nil) {
        self.transactions = transactions
        self.error = error
    }

    func fetchTransactions(in period: DateInterval?) async throws(DomainError) -> [Transaction] {
        requestedPeriods.append(period)
        if let error {
            throw error
        }
        return transactions
    }

    func addTransaction(_ transaction: Transaction) async throws(DomainError) {
        if let error {
            throw error
        }
        added.append(transaction)
    }

    func deleteTransaction(id: UUID) async throws(DomainError) {
        if let error {
            throw error
        }
        deletedIDs.append(id)
    }
}

// MARK: - Fixtures

enum Fixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    static let march2026 = YearMonth(year: 2026, month: 3) ?? YearMonth(containing: .now, calendar: calendar)

    static let salary = TransactionCategory(id: "salary", name: "Salario", kind: .income)
    static let groceries = TransactionCategory(id: "groceries", name: "Supermercado", kind: .expense)

    /// Built from a string: `Decimal(0.1)` would go through `Double` and be inexact.
    static func decimal(_ string: String) -> Decimal {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) ?? .nan
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    static func transaction(
        _ amount: String,
        _ kind: TransactionKind,
        on date: Date = date(2026, 3, 15),
        currency: String = "USD",
        status: TransactionStatus = .confirmed,
        note: String? = nil,
    ) -> Transaction {
        Transaction(
            amount: decimal(amount),
            currency: currency,
            kind: kind,
            category: kind == .income ? salary : groceries,
            date: date,
            note: note,
            status: status,
        )
    }
}
