import Domain
import Foundation

/// The last months side by side, each with its totals and categories, in the principal currency.
public struct SummaryReport: Hashable, Sendable {
    public let currency: String
    /// Oldest first; the last one is the current month.
    public let months: [MonthlySummary]
    /// Averages over the months that had any movement of that kind (`SpendingHistory`).
    public let averageExpense: Decimal?
    public let averageIncome: Decimal?
    public let categories: [TransactionCategory]

    public init(
        currency: String,
        months: [MonthlySummary],
        averageExpense: Decimal?,
        averageIncome: Decimal?,
        categories: [TransactionCategory],
    ) {
        self.currency = currency
        self.months = months
        self.averageExpense = averageExpense
        self.averageIncome = averageIncome
        self.categories = categories
    }
}

public protocol GetSummaryReportUseCase: Sendable {
    func execute() async throws(DomainError) -> SummaryReport
}

public struct DefaultGetSummaryReportUseCase: GetSummaryReportUseCase {
    /// The design's six bars.
    public static let monthCount = 6

    private let transactions: any TransactionRepository
    private let categories: any CategoryRepository
    private let settings: any SettingsRepository
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        transactions: any TransactionRepository,
        categories: any CategoryRepository,
        settings: any SettingsRepository,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now },
    ) {
        self.transactions = transactions
        self.categories = categories
        self.settings = settings
        self.calendar = calendar
        self.now = now
    }

    public func execute() async throws(DomainError) -> SummaryReport {
        let currency = try await settings.load()?.currencies.principal ?? "USD"
        return try await Self.report(
            transactions: transactions.fetchTransactions(in: nil),
            categories: categories.fetchCategories(),
            currency: currency,
            calendar: calendar,
            now: now(),
        )
    }

    static func report(
        transactions: [Transaction],
        categories: [TransactionCategory],
        currency: String,
        calendar: Calendar,
        now: Date,
    ) -> SummaryReport {
        let current = YearMonth(containing: now, calendar: calendar)
        let months = (0 ..< monthCount).reversed().map { offset in
            MonthlySummary(month: current.adding(months: -offset), transactions: transactions, currency: currency, calendar: calendar)
        }
        return SummaryReport(
            currency: currency,
            months: months,
            averageExpense: SpendingHistory.averageMonthlyTotal(of: .expense, transactions: transactions, calendar: calendar),
            averageIncome: SpendingHistory.averageMonthlyTotal(of: .income, transactions: transactions, calendar: calendar),
            categories: categories,
        )
    }
}
