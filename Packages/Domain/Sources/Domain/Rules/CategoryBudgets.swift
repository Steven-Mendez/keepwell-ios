import Foundation

/// How one budgeted expense category is doing in a month. Summary lists these and home warns
/// about the ones near or over their line; both read them from here so they never disagree.
public struct CategoryBudgetStatus: Hashable, Sendable {
    public enum Level: String, Hashable, Sendable {
        /// Under `nearLimitRatio`.
        case onTrack
        /// From `nearLimitRatio` up to, not including, the whole budget.
        case nearLimit
        /// The whole budget or more.
        case exceeded
    }

    /// Where a budget starts warning. Shared with the web app, so both warn at the same amount.
    public static let nearLimitRatio = Decimal(string: "0.8") ?? 0
    public static let exceededRatio = Decimal(1)

    public let categoryID: String
    /// Confirmed spending this month, in the principal currency.
    public let spent: Money
    public let budget: Money
    /// `spent / budget`; 1 is the whole budget, and it keeps growing past it.
    public let ratio: Decimal
    public let level: Level

    public init(categoryID: String, spent: Money, budget: Money) {
        self.categoryID = categoryID
        self.spent = spent
        self.budget = budget
        ratio = budget.amount > 0 ? spent.amount / budget.amount : 0
        level = Self.level(for: ratio)
    }

    public static func level(for ratio: Decimal) -> Level {
        if ratio >= exceededRatio {
            .exceeded
        } else if ratio >= nearLimitRatio {
            .nearLimit
        } else {
            .onTrack
        }
    }

    /// What is left (positive) or how far over it went (negative).
    public var remaining: Decimal {
        budget.amount - spent.amount
    }

    /// One status per expense category with a budget in `currency`, most used first. A budget
    /// set in another currency (the person changed their principal since) is left out instead of
    /// converted: a rate picked today would quietly move the line they drew. A budgeted category
    /// with nothing spent still appears, at zero, so the person sees all of their budgets.
    ///
    /// - Parameter totals: the month's confirmed spending per category in the principal
    ///   currency, as `MonthlySummary.categories` holds it.
    public static func statuses(
        totals: [MonthlySummary.CategoryTotal],
        categories: [TransactionCategory],
        currency: String,
    ) -> [Self] {
        let spent = Dictionary(totals.map { ($0.categoryID, $0.amount) }, uniquingKeysWith: +)
        return categories
            .compactMap { category -> Self? in
                guard category.kind == .expense,
                      let budget = category.monthlyBudget,
                      budget.currency == currency,
                      budget.amount > 0
                else { return nil }
                return Self(categoryID: category.id, spent: Money(spent[category.id] ?? 0, currency), budget: budget)
            }
            .sorted { $0.ratio == $1.ratio ? $0.categoryID < $1.categoryID : $0.ratio > $1.ratio }
    }

    /// The statuses of `month`, in its currency.
    public static func statuses(of month: MonthlySummary, categories: [TransactionCategory]) -> [Self] {
        statuses(totals: month.categories, categories: categories, currency: month.currency)
    }
}
