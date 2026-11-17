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
    /// Income and expenses of the month the totals leave out: their stored rate doesn't reach
    /// `currency` (recorded before the main currency changed). Empty when every movement counts.
    public let excluded: [UnconvertedMovements]

    /// `income − expense`; negative when the month overspent.
    public var savings: Decimal {
        income - expense
    }

    /// `savings / income` (0.71 = 71%). `nil` without income: the ratio is undefined and showing
    /// 0% would hide overspending.
    public var savingsRate: Decimal? {
        income > 0 ? savings / income : nil
    }

    /// With `debts`, an expense counts only the person's part (`Transaction.spendingAmount(in:debts:)`)
    /// and an income that deposited a debt repayment doesn't count at all.
    public init(month: YearMonth, transactions: [Transaction], currency: String, calendar: Calendar, debts: DebtLinks = .empty) {
        var income = Decimal(0)
        var expense = Decimal(0)
        var perCategory: [String: Decimal] = [:]
        var perIncomeCategory: [String: Decimal] = [:]
        var excluded = UnconvertedMovements.Tally()
        for transaction in transactions
            where transaction.isConfirmed && transaction.kind != .transfer
            && YearMonth(containing: transaction.date, calendar: calendar) == month
        {
            if transaction.isReimbursement(debts) {
                continue
            }
            guard let amount = transaction.summaryAmount(in: currency, debts: debts) else {
                excluded.add(transaction)
                continue
            }
            // A movement entirely paid for by others adds nothing, not even an empty category.
            if amount == 0 {
                continue
            }
            switch transaction.kind {
            case .income:
                income += amount
                perIncomeCategory[transaction.categoryID ?? TransactionCategory.otherIncomeID, default: 0] += amount
            case .expense:
                expense += amount
                perCategory[transaction.categoryID ?? TransactionCategory.otherExpenseID, default: 0] += amount
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
        self.excluded = excluded.entries
    }

    private static func ranked(_ totals: [String: Decimal], total: Decimal) -> [CategoryTotal] {
        totals
            .map { CategoryTotal(categoryID: $0.key, amount: $0.value, share: total > 0 ? $0.value / total : 0) }
            .sorted { $0.amount == $1.amount ? $0.categoryID < $1.categoryID : $0.amount > $1.amount }
    }
}

/// Movements in one currency whose stored rate doesn't reach a total's currency, so it doesn't
/// count them.
public struct UnconvertedMovements: Hashable, Sendable {
    public let currency: String
    public let count: Int

    public init(currency: String, count: Int) {
        self.currency = currency
        self.count = count
    }

    /// What a total left out, by the movements' own currency.
    public struct Tally: Sendable {
        private var counts: [String: Int] = [:]

        public init() {}

        public mutating func add(_ transaction: Transaction) {
            counts[transaction.currency, default: 0] += 1
        }

        /// Sorted by currency code; empty when every movement was counted.
        public var entries: [UnconvertedMovements] {
            counts.sorted { $0.key < $1.key }.map { UnconvertedMovements(currency: $0.key, count: $0.value) }
        }
    }
}

public enum SpendingHistory {
    /// Monthly spending for `count` months ending at `last`, oldest first (the summary bars).
    public static func monthlyExpenses(
        endingAt last: YearMonth,
        count: Int,
        transactions: [Transaction],
        currency: String,
        calendar: Calendar,
        debts: DebtLinks = .empty,
    ) -> [(month: YearMonth, expense: Decimal)] {
        monthlyTotals(
            of: .expense, endingAt: last, count: count, transactions: transactions, currency: currency, calendar: calendar, debts: debts,
        )
        .map { (month: $0.month, expense: $0.total) }
    }

    /// Monthly totals of one kind (expense or income) in `currency` for `count` months ending at
    /// `last`, oldest first.
    public static func monthlyTotals( // swiftlint:disable:this function_parameter_count
        of kind: TransactionKind,
        endingAt last: YearMonth,
        count: Int,
        transactions: [Transaction],
        currency: String,
        calendar: Calendar,
        debts: DebtLinks = .empty,
    ) -> [(month: YearMonth, total: Decimal)] {
        let totals = totalsByMonth(of: kind, transactions, currency: currency, calendar: calendar, debts: debts)
        return (0 ..< count).reversed().map { offset in
            let month = last.adding(months: -offset)
            return (month, totals[month] ?? 0)
        }
    }

    /// Average monthly spending over the months that have any spending, so months before the
    /// person started using the app don't drag it down. `nil` when nothing was spent yet.
    public static func averageMonthlyExpense(
        transactions: [Transaction],
        currency: String,
        calendar: Calendar,
        debts: DebtLinks = .empty,
    ) -> Decimal? {
        averageMonthlyTotal(of: .expense, transactions: transactions, currency: currency, calendar: calendar, debts: debts)
    }

    /// Same rule as `averageMonthlyExpense`, for either direction.
    public static func averageMonthlyTotal(
        of kind: TransactionKind,
        transactions: [Transaction],
        currency: String,
        calendar: Calendar,
        debts: DebtLinks = .empty,
    ) -> Decimal? {
        let totals = totalsByMonth(of: kind, transactions, currency: currency, calendar: calendar, debts: debts).values.filter { $0 > 0 }
        guard !totals.isEmpty else { return nil }
        return totals.reduce(0, +) / Decimal(totals.count)
    }

    /// Totals in `currency`, read as `MonthlySummary` does (`summaryAmount`), leaving out what can't
    /// be converted.
    private static func totalsByMonth(
        of kind: TransactionKind,
        _ transactions: [Transaction],
        currency: String,
        calendar: Calendar,
        debts: DebtLinks,
    ) -> [YearMonth: Decimal] {
        transactions
            .filter { $0.isConfirmed && $0.kind == kind && !$0.isReimbursement(debts) }
            .reduce(into: [:]) { totals, transaction in
                let amount = kind == .transfer
                    ? transaction.storedAmount(in: currency)
                    : transaction.summaryAmount(in: currency, debts: debts)
                guard let amount, amount != 0 else { return }
                totals[YearMonth(containing: transaction.date, calendar: calendar), default: 0] += amount
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
