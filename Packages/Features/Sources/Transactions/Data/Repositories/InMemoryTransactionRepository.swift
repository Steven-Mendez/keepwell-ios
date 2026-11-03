import Domain
import Foundation
import TransactionsDomain

/// Same contract as `SwiftDataTransactionRepository` without a `ModelContainer`: for `#Preview`,
/// UI tests and integration tests that need realistic data quickly.
public actor InMemoryTransactionRepository: TransactionRepository {
    private var storage: [UUID: Transaction]

    public init(transactions: [Transaction] = []) {
        storage = Dictionary(transactions.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    public func fetchTransactions(in period: DateInterval?) async throws(DomainError) -> [Transaction] {
        storage.values
            .filter { transaction in
                guard let period else { return true }
                return transaction.date >= period.start && transaction.date < period.end
            }
            .sorted { $0.date > $1.date }
    }

    public func addTransaction(_ transaction: Transaction) async throws(DomainError) {
        storage[transaction.id] = transaction
    }

    public func deleteTransaction(id: UUID) async throws(DomainError) {
        guard storage.removeValue(forKey: id) != nil else { throw .notFound(id) }
    }
}

public enum TransactionSeed {
    private struct Entry {
        let day: Int
        let amount: String
        let currency: String
        let categoryID: String
        var note: String?
        var status = TransactionStatus.confirmed
    }

    /// A month that exercises every summary rule: income and expenses in USD, one NIO expense
    /// (excluded from the USD summary) and one planned expense (excluded until confirmed).
    public static func sample(for month: YearMonth, calendar: Calendar = .current) -> [Transaction] {
        let entries = [
            Entry(day: 1, amount: "2500.00", currency: "USD", categoryID: "salary"),
            Entry(day: 3, amount: "182.45", currency: "USD", categoryID: "groceries", note: "Compra quincenal"),
            Entry(day: 5, amount: "64.90", currency: "USD", categoryID: "restaurants"),
            Entry(day: 8, amount: "950.00", currency: "NIO", categoryID: "transport", note: "Taxis de la semana"),
            Entry(day: 12, amount: "350.00", currency: "USD", categoryID: "extra", note: "Proyecto freelance"),
            Entry(day: 14, amount: "420.00", currency: "USD", categoryID: "housing"),
            Entry(day: 20, amount: "15.99", currency: "USD", categoryID: "subscriptions", status: .planned),
        ]
        let categories = TransactionCategory.defaultExpense + TransactionCategory.defaultIncome
        return entries.compactMap { entry in
            guard let category = categories.first(where: { $0.id == entry.categoryID }),
                  let amount = Decimal(string: entry.amount, locale: Locale(identifier: "en_US_POSIX")),
                  let date = calendar.date(from: DateComponents(year: month.year, month: month.month, day: entry.day, hour: 12))
            else { return nil }
            return Transaction(
                amount: amount,
                currency: entry.currency,
                kind: category.kind,
                category: category,
                date: date,
                note: entry.note,
                status: entry.status,
            )
        }
    }
}
