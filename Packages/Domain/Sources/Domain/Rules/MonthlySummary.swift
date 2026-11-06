import Foundation

/// HANDOFF rule 7, in the principal currency. Only confirmed expenses and income count;
/// transfers move money without spending it.
public struct MonthlySummary: Hashable, Sendable {
    public struct CategoryTotal: Hashable, Sendable {
        public let categoryID: String
        public let amount: Decimal
        /// Share of the month's spending (0…1).
        public let share: Decimal
    }

    public let month: YearMonth
    public let currency: String
    public let income: Decimal
    public let expense: Decimal
    /// Spending per category, largest first.
    public let categories: [CategoryTotal]
    /// Income per category, largest first; shares are of the month's income.
    public let incomeCategories: [CategoryTotal]

    /// `income − expense`; negative when the month overspent.
    public var savings: Decimal {
        income - expense
    }

    /// `savings / income` (0.71 = 71%). `nil` without income: the ratio is undefined and showing
    /// 0% would hide overspending.
    public var savingsRate: Decimal? {
        income > 0 ? savings / income : nil
    }

    public init(month: YearMonth, transactions: [Transaction], currency: String, calendar: Calendar) {
        var income = Decimal(0)
        var expense = Decimal(0)
        var perCategory: [String: Decimal] = [:]
        var perIncomeCategory: [String: Decimal] = [:]
        for transaction in transactions
            where transaction.isConfirmed && YearMonth(containing: transaction.date, calendar: calendar) == month
        {
            switch transaction.kind {
            case .income:
                income += transaction.principalAmount
                perIncomeCategory[transaction.categoryID ?? TransactionCategory.otherIncomeID, default: 0] += transaction.principalAmount
            case .expense:
                expense += transaction.principalAmount
                perCategory[transaction.categoryID ?? TransactionCategory.otherExpenseID, default: 0] += transaction.principalAmount
            case .transfer:
                continue
            }
        }
        self.month = month
        self.currency = currency
        self.income = income
        self.expense = expense
        categories = Self.ranked(perCategory, total: expense)
        incomeCategories = Self.ranked(perIncomeCategory, total: income)
    }

    private static func ranked(_ totals: [String: Decimal], total: Decimal) -> [CategoryTotal] {
        totals
            .map { CategoryTotal(categoryID: $0.key, amount: $0.value, share: total > 0 ? $0.value / total : 0) }
            .sorted { $0.amount == $1.amount ? $0.categoryID < $1.categoryID : $0.amount > $1.amount }
    }
}

public enum SpendingHistory {
    /// Monthly spending for `count` months ending at `last`, oldest first (the summary bars).
    public static func monthlyExpenses(
        endingAt last: YearMonth,
        count: Int,
        transactions: [Transaction],
        calendar: Calendar,
    ) -> [(month: YearMonth, expense: Decimal)] {
        monthlyTotals(of: .expense, endingAt: last, count: count, transactions: transactions, calendar: calendar)
            .map { (month: $0.month, expense: $0.total) }
    }

    /// Monthly totals of one kind (expense or income) for `count` months ending at `last`, oldest first.
    public static func monthlyTotals(
        of kind: TransactionKind,
        endingAt last: YearMonth,
        count: Int,
        transactions: [Transaction],
        calendar: Calendar,
    ) -> [(month: YearMonth, total: Decimal)] {
        let totals = totalsByMonth(of: kind, transactions, calendar: calendar)
        return (0 ..< count).reversed().map { offset in
            let month = last.adding(months: -offset)
            return (month, totals[month] ?? 0)
        }
    }

    /// Average monthly spending over the months that have any spending, so months before the
    /// person started using the app don't drag it down. `nil` when nothing was spent yet.
    public static func averageMonthlyExpense(transactions: [Transaction], calendar: Calendar) -> Decimal? {
        averageMonthlyTotal(of: .expense, transactions: transactions, calendar: calendar)
    }

    /// Same rule as `averageMonthlyExpense`, for either direction.
    public static func averageMonthlyTotal(of kind: TransactionKind, transactions: [Transaction], calendar: Calendar) -> Decimal? {
        let totals = totalsByMonth(of: kind, transactions, calendar: calendar).values.filter { $0 > 0 }
        guard !totals.isEmpty else { return nil }
        return totals.reduce(0, +) / Decimal(totals.count)
    }

    private static func totalsByMonth(of kind: TransactionKind, _ transactions: [Transaction], calendar: Calendar) -> [YearMonth: Decimal] {
        transactions
            .filter { $0.isConfirmed && $0.kind == kind }
            .reduce(into: [:]) { totals, transaction in
                totals[YearMonth(containing: transaction.date, calendar: calendar), default: 0] += transaction.principalAmount
            }
    }
}

/// Planned movements waiting for confirmation ("Previstos · 4 … C$7,500 (≈ $204.78)").
public struct PlannedSummary: Hashable, Sendable {
    public let count: Int
    public let principalTotal: Decimal
    public let secondTotal: Decimal

    public init(transactions: [Transaction]) {
        let planned = transactions.filter { !$0.isConfirmed }
        count = planned.count
        principalTotal = planned.reduce(0) { $0 + $1.principalAmount }
        secondTotal = planned.reduce(0) { $0 + $1.secondAmount }
    }
}
