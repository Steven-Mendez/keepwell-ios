import Domain
import Foundation

/// A category in the period next to what it was in the comparison period.
public struct CategoryChange: Hashable, Sendable {
    public let categoryID: String
    public let amount: Decimal
    /// Share of the period's total (0...1).
    public let share: Decimal
    public let previous: Decimal
    /// `amount - previous`; positive means more than before.
    public let change: Decimal
    /// `change / previous`; `nil` when the category is new, where a percentage means nothing.
    public let changeRate: Decimal?
}

/// One category's amount per month of the period, in the period's order.
public struct CategoryTrend: Hashable, Sendable {
    public let categoryID: String
    public let amounts: [Decimal]
}

/// One calendar year's totals, for the year-over-year bars.
public struct YearTotals: Hashable, Sendable {
    public let year: Int
    public let cashFlow: CashFlowTrend
    /// The running year: its total is only through today.
    public let isRunning: Bool
}

/// Everything the range view draws for `range`, in the principal currency (every movement already
/// carries its own stored rate, so nothing here adds two currencies).
public struct TrendReport: Hashable, Sendable {
    public static let categoryCount = 4

    public let currency: String
    public let range: MonthRange
    public let comparison: MonthRange
    /// One per month of `range`, oldest first.
    public let months: [MonthlySummary]
    /// Aligned with `months`: index 3 here is index 3 there.
    public let comparisonMonths: [MonthlySummary]
    public let cashFlow: CashFlowTrend
    public let comparisonCashFlow: CashFlowTrend
    /// Whether the comparison had any income or spending; without it every "vs" is noise.
    public let hasComparison: Bool
    /// The running month is in the range, so the period isn't over (and was compared to the same day).
    public let isRunning: Bool
    /// Per month, over the months that had spending (or income).
    public let averageExpense: Decimal?
    public let averageIncome: Decimal?
    /// The month that kept the most and the one that kept the least; only months with movements.
    public let bestMonth: MonthlySummary?
    public let worstMonth: MonthlySummary?
    /// Every category of either period, largest in this one first.
    public let expenseCategories: [CategoryChange]
    public let incomeCategories: [CategoryChange]
    /// The category whose spending grew the most in money, and the one that dropped the most.
    public let biggestIncrease: CategoryChange?
    public let biggestDecrease: CategoryChange?
    /// Savings added up month by month, so the last point is the period's total.
    public let cumulativeSavings: [Decimal]
    public let comparisonCumulativeSavings: [Decimal]
    /// The largest spending categories, month by month.
    public let categoryTrends: [CategoryTrend]

    /// Months that had any income or spending.
    public var activeMonthCount: Int {
        months.count { $0.income > 0 || $0.expense > 0 }
    }
}

/// The report, the span the ledger covers (for the custom pickers) and the yearly totals.
public struct RangeSummary: Hashable, Sendable {
    public let report: TrendReport
    public let activity: MonthRange
    public let years: [YearTotals]
}

extension TrendReport {
    private static func counts(_ transaction: Transaction) -> Bool {
        transaction.isConfirmed && transaction.kind != .transfer
    }

    private static func byMonth(_ transactions: [Transaction], until: Date? = nil, calendar: Calendar) -> [YearMonth: [Transaction]] {
        var buckets: [YearMonth: [Transaction]] = [:]
        for transaction in transactions where counts(transaction) {
            if let until, transaction.date > until {
                continue
            }
            buckets[YearMonth(containing: transaction.date, calendar: calendar), default: []].append(transaction)
        }
        return buckets
    }

    /// First month with confirmed income or spending through the running month; `nil` before any.
    static func activityRange(of transactions: [Transaction], now: Date, calendar: Calendar) -> MonthRange? {
        let first = transactions.filter(counts).map { YearMonth(containing: $0.date, calendar: calendar) }.min()
        return first.map { MonthRange($0, YearMonth(containing: now, calendar: calendar)) }
    }

    private static func average(of values: [Decimal]) -> Decimal? {
        let active = values.filter { $0 > 0 }
        return active.isEmpty ? nil : active.reduce(0, +) / Decimal(active.count)
    }

    private static func running(_ values: [Decimal]) -> [Decimal] {
        var total = Decimal(0)
        return values.map { value in
            total += value
            return total
        }
    }

    private static func totals(of months: [MonthlySummary], pick: (MonthlySummary) -> [MonthlySummary.CategoryTotal]) -> [String: Decimal] {
        var totals: [String: Decimal] = [:]
        for month in months {
            for entry in pick(month) {
                totals[entry.categoryID, default: 0] += entry.amount
            }
        }
        return totals
    }

    private static func changes(current: [String: Decimal], previous: [String: Decimal]) -> [CategoryChange] {
        let total = current.values.reduce(0, +)
        let ids = Set(current.keys).union(previous.keys)
        return ids
            .map { id in
                let amount = current[id] ?? 0
                let before = previous[id] ?? 0
                let change = amount - before
                return CategoryChange(
                    categoryID: id,
                    amount: amount,
                    share: total > 0 ? amount / total : 0,
                    previous: before,
                    change: change,
                    changeRate: before > 0 ? change / before : nil,
                )
            }
            .sorted {
                if $0.amount != $1.amount {
                    return $0.amount > $1.amount
                }
                if $0.previous != $1.previous {
                    return $0.previous > $1.previous
                }
                return $0.categoryID < $1.categoryID
            }
    }

    /// The month that kept the most and the one that kept the least; only months with movements,
    /// and no worst month when there is a single one.
    private static func bestAndWorst(of months: [MonthlySummary]) -> (MonthlySummary?, MonthlySummary?) {
        let active = months.filter { $0.income > 0 || $0.expense > 0 }
        let bySavings = stableSorted(active) { lhs, rhs in
            lhs.savings != rhs.savings ? lhs.savings > rhs.savings : lhs.month < rhs.month
        }
        return (bySavings.first, bySavings.count > 1 ? bySavings.last : nil)
    }

    /// Stable sort: ties keep their order, like the web's `Array.sort`.
    private static func stableSorted<T>(_ values: [T], by areInOrder: (T, T) -> Bool) -> [T] {
        values.enumerated()
            .sorted { areInOrder($0.element, $1.element) || (!areInOrder($1.element, $0.element) && $0.offset < $1.offset) }
            .map(\.element)
    }

    /// Confirmed movements bucketed by month, in one currency, ready to summarize any span.
    private struct Ledger {
        let buckets: [YearMonth: [Transaction]]
        let currency: String
        let calendar: Calendar

        func summaries(of range: MonthRange, lastMonthBuckets: [YearMonth: [Transaction]]? = nil) -> [MonthlySummary] {
            range.months.enumerated().map { index, month in
                let source = index == range.length - 1 ? lastMonthBuckets ?? buckets : buckets
                return MonthlySummary(month: month, transactions: source[month] ?? [], currency: currency, calendar: calendar)
            }
        }
    }

    /// Months after the running one are dropped, since they can't have confirmed movements yet.
    /// When the running month is in the range, its counterpart in the comparison is cut at the
    /// same day, so a half-finished November isn't measured against a whole one.
    public init(transactions: [Transaction], currency: String, requested: MonthRange, now: Date, calendar: Calendar) {
        let current = YearMonth(containing: now, calendar: calendar)
        let range = MonthRange(requested.start, min(requested.end, current))
        let isRunning = range.end == current
        let shift = range.comparisonShift
        let comparison = range.shifted(by: -shift)

        let ledger = Ledger(buckets: Self.byMonth(transactions, calendar: calendar), currency: currency, calendar: calendar)
        let months = ledger.summaries(of: range)
        // Only the running month's counterpart is cut; the rest of the comparison is whole months.
        let cut = isRunning
            ? Self.byMonth(transactions, until: calendar.date(byAdding: .month, value: -shift, to: now), calendar: calendar)
            : nil
        let comparisonMonths = ledger.summaries(of: comparison, lastMonthBuckets: cut)

        let cashFlow = CashFlowTrend(months: months)
        let comparisonCashFlow = CashFlowTrend(months: comparisonMonths)

        let (best, worst) = Self.bestAndWorst(of: months)

        let expenseCategories = Self.changes(
            current: Self.totals(of: months, pick: \.categories),
            previous: Self.totals(of: comparisonMonths, pick: \.categories),
        )

        // A category that grew from nothing is "new", not "up"; only compare when the old period spent.
        let comparable = comparisonCashFlow.expense > 0 ? expenseCategories : []
        let increases = Self.stableSorted(comparable.filter { $0.change > 0 }) { $0.change > $1.change }
        let decreases = Self.stableSorted(comparable.filter { $0.change < 0 }) { $0.change < $1.change }

        self.currency = currency
        self.range = range
        self.comparison = comparison
        self.months = months
        self.comparisonMonths = comparisonMonths
        self.cashFlow = cashFlow
        self.comparisonCashFlow = comparisonCashFlow
        hasComparison = comparisonCashFlow.income > 0 || comparisonCashFlow.expense > 0
        self.isRunning = isRunning
        averageExpense = Self.average(of: months.map(\.expense))
        averageIncome = Self.average(of: months.map(\.income))
        bestMonth = best
        worstMonth = worst
        self.expenseCategories = expenseCategories
        incomeCategories = Self.changes(
            current: Self.totals(of: months, pick: \.incomeCategories),
            previous: Self.totals(of: comparisonMonths, pick: \.incomeCategories),
        )
        biggestIncrease = increases.first
        biggestDecrease = decreases.first
        cumulativeSavings = Self.running(months.map(\.savings))
        comparisonCumulativeSavings = Self.running(comparisonMonths.map(\.savings))
        categoryTrends = expenseCategories.filter { $0.amount > 0 }.prefix(Self.categoryCount).map { entry in
            CategoryTrend(
                categoryID: entry.categoryID,
                amounts: months.map { month in month.categories.first { $0.categoryID == entry.categoryID }?.amount ?? 0 },
            )
        }
    }

    /// Every year from the first movement through the running one, oldest first.
    static func yearTotals(of transactions: [Transaction], currency: String, now: Date, calendar: Calendar) -> [YearTotals] {
        guard let activity = activityRange(of: transactions, now: now, calendar: calendar) else { return [] }
        let buckets = byMonth(transactions, calendar: calendar)
        return (activity.start.year ... activity.end.year).map { year in
            let first = activity.start.adding(months: -(activity.start.month - 1) + 12 * (year - activity.start.year))
            let months = MonthRange(first, first.adding(months: 11)).months.map {
                MonthlySummary(month: $0, transactions: buckets[$0] ?? [], currency: currency, calendar: calendar)
            }
            return YearTotals(year: year, cashFlow: CashFlowTrend(months: months), isRunning: year == activity.end.year)
        }
    }
}

public protocol GetRangeSummaryUseCase: Sendable {
    /// `custom` only matters for `.custom`. `nil` for `.month`, which `GetSummaryReportUseCase` serves.
    func execute(period: SummaryPeriod, custom: MonthRange?) async throws(DomainError) -> RangeSummary?
}

public struct DefaultGetRangeSummaryUseCase: GetRangeSummaryUseCase {
    private let transactions: any TransactionRepository
    private let settings: any SettingsRepository
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        transactions: any TransactionRepository,
        settings: any SettingsRepository,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now },
    ) {
        self.transactions = transactions
        self.settings = settings
        self.calendar = calendar
        self.now = now
    }

    public func execute(period: SummaryPeriod, custom: MonthRange?) async throws(DomainError) -> RangeSummary? {
        let now = now()
        guard let requested = period.range(custom: custom, now: now, calendar: calendar) else { return nil }
        let currency = try await settings.load()?.currencies.principal ?? CurrencySettings.initial.principal
        let all = try await transactions.fetchTransactions(in: nil)
        let report = TrendReport(transactions: all, currency: currency, requested: requested, now: now, calendar: calendar)
        return RangeSummary(
            report: report,
            // Reaches back to the first movement for the pickers; a ledger without any shows a year.
            activity: TrendReport.activityRange(of: all, now: now, calendar: calendar) ?? .lastMonths(12, now: now, calendar: calendar),
            years: TrendReport.yearTotals(of: all, currency: currency, now: now, calendar: calendar),
        )
    }
}
