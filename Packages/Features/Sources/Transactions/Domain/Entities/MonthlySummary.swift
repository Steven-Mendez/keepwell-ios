import Foundation

/// Totals for one month in **one** currency: adding USD to NIO needs an exchange rate, which this
/// summary deliberately doesn't apply.
public struct MonthlySummary: Hashable, Sendable {
    public let month: YearMonth
    public let currency: String
    public let totalIncome: Decimal
    public let totalExpense: Decimal
    /// `totalIncome - totalExpense`; negative when the month overspent.
    public let netBalance: Decimal
    /// `netBalance / totalIncome` as a fraction (0.25 = 25 %), rounded to 4 places.
    /// `nil` when there is no income: the ratio is undefined, and reporting 0 % would hide overspending.
    public let savingsRate: Decimal?

    public init(
        month: YearMonth,
        currency: String,
        totalIncome: Decimal,
        totalExpense: Decimal,
        netBalance: Decimal,
        savingsRate: Decimal?,
    ) {
        self.month = month
        self.currency = currency
        self.totalIncome = totalIncome
        self.totalExpense = totalExpense
        self.netBalance = netBalance
        self.savingsRate = savingsRate
    }
}
