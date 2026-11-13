import Domain
import Foundation

/// The last months side by side, each with its totals and categories, in the principal currency.
/// Every amount comes from `Transaction.principalAmount`, converted with the rate stored on each
/// movement, so the charts never add two currencies together.
public struct SummaryReport: Hashable, Sendable {
    public let currency: String
    /// Oldest first; the last one is the current month.
    public let months: [MonthlySummary]
    /// Averages over the months that had any movement of that kind (`SpendingHistory`).
    public let averageExpense: Decimal?
    public let averageIncome: Decimal?
    public let categories: [TransactionCategory]
    /// The whole window added up, for "in six months you saved…".
    public let cashFlow: CashFlowTrend
    /// Same order as `months`.
    public let expenseBreakdowns: [CategoryBreakdown]
    public let incomeBreakdowns: [CategoryBreakdown]
    /// Same order as `months`, each against the month before it.
    public let paces: [SpendingPace]
    /// Same order as `months`: how each budgeted category did that month, closest to its limit first.
    public let budgets: [[CategoryBudgetStatus]]
    /// The budgets `budgets` leaves out for being in another currency (the principal changed since),
    /// counted per currency so the card can name them instead of converting.
    public let otherCurrencyBudgets: [OtherCurrencyBudgets]
    /// Net worth at the end of each of the last twelve months (`NetWorthHistory`), oldest first.
    public let netWorth: [NetWorthHistory.Point]
    /// Whether a second currency goes into net worth, each month at its own rate, which the card then
    /// says.
    public let convertsCurrencies: Bool

    public init(
        currency: String,
        months: [MonthlySummary],
        averageExpense: Decimal?,
        averageIncome: Decimal?,
        categories: [TransactionCategory],
        paces: [SpendingPace],
        netWorth: [NetWorthHistory.Point] = [],
        convertsCurrencies: Bool = false,
    ) {
        self.currency = currency
        self.months = months
        self.averageExpense = averageExpense
        self.averageIncome = averageIncome
        self.categories = categories
        self.paces = paces
        self.netWorth = netWorth
        self.convertsCurrencies = convertsCurrencies
        cashFlow = CashFlowTrend(months: months)
        expenseBreakdowns = months.map { CategoryBreakdown(totals: $0.categories) }
        incomeBreakdowns = months.map { CategoryBreakdown(totals: $0.incomeCategories) }
        // Today's budgets measure past months too: the app keeps no history of budget changes.
        budgets = months.map { CategoryBudgetStatus.statuses(of: $0, categories: categories) }
        otherCurrencyBudgets = OtherCurrencyBudgets.of(categories: categories, currency: currency)
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
    private let accounts: (any AccountRepository)?
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        transactions: any TransactionRepository,
        categories: any CategoryRepository,
        settings: any SettingsRepository,
        accounts: (any AccountRepository)? = nil,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now },
    ) {
        self.transactions = transactions
        self.categories = categories
        self.settings = settings
        self.accounts = accounts
        self.calendar = calendar
        self.now = now
    }

    public func execute() async throws(DomainError) -> SummaryReport {
        let currencies = try await settings.load()?.currencies ?? .initial
        return try await Self.report(
            transactions: transactions.fetchTransactions(in: nil),
            categories: categories.fetchCategories(),
            currency: currencies.principal,
            accounts: accounts?.fetchAccounts() ?? [],
            currencies: currencies,
            calendar: calendar,
            now: now(),
        )
    }

    static func report(
        transactions: [Transaction],
        categories: [TransactionCategory],
        currency: String,
        accounts: [Account] = [],
        currencies: CurrencySettings? = nil,
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
            paces: months.map { SpendingPace(month: $0.month, transactions: transactions, calendar: calendar, now: now) },
            // A currency the settings no longer convert leaves the card out rather than the summary.
            netWorth: currencies.flatMap {
                try? NetWorthHistory.points(accounts: accounts, transactions: transactions, settings: $0, now: now, calendar: calendar)
            } ?? [],
            convertsCurrencies: currencies?.second != nil,
        )
    }
}
