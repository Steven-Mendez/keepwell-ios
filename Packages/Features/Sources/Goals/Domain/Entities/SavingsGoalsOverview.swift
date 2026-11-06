import Domain
import Foundation

/// Everything the goals screen shows: each goal with its progress, in the order lists use, and
/// the currencies a new goal may be set in.
public struct SavingsGoalsOverview: Hashable, Sendable {
    public let currencies: CurrencySettings
    /// The month "this month" and "a month" are counted from.
    public let currentMonth: YearMonth
    /// Open goals first (soonest target month first), then those without a date, reached ones last.
    public let goals: [SavingsGoalProgress]

    public init(currencies: CurrencySettings, currentMonth: YearMonth, goals: [SavingsGoal]) {
        self.currencies = currencies
        self.currentMonth = currentMonth
        self.goals = SavingsGoalProgress.ordered(goals, currentMonth: currentMonth)
    }

    public func progress(of id: UUID) -> SavingsGoalProgress? {
        goals.first { $0.goal.id == id }
    }
}
