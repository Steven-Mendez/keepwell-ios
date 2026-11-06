import Foundation

/// How far a savings goal is and what it asks for each month. The goals screen and home both read
/// it from here, and the web app follows the same rules, so the figure never differs between them.
public struct SavingsGoalProgress: Hashable, Sendable {
    public let goal: SavingsGoal
    /// What is still missing, never below zero.
    public let remaining: Decimal
    /// `saved / target`, unclamped: past 1 the goal was overshot, and the UI clamps the bar.
    public let fraction: Decimal
    public let isReached: Bool
    /// Months from the current one through the target month, both included (November to December
    /// is 2, the same month is 1). `nil` without a target month or once it has passed.
    public let monthsLeft: Int?
    /// The target month passed before the goal was reached.
    public let isOverdue: Bool
    /// What to set aside each month to arrive on time, rounded up to the cent so following it
    /// never falls short. `nil` when reached, overdue or without a target month.
    public let monthlyAmount: Decimal?

    public init(goal: SavingsGoal, currentMonth: YearMonth) {
        self.goal = goal
        let target = goal.target.amount
        remaining = max(target - goal.saved, 0)
        fraction = target > 0 ? goal.saved / target : 0
        isReached = goal.saved >= target
        guard let targetMonth = goal.targetMonth else {
            monthsLeft = nil
            isOverdue = false
            monthlyAmount = nil
            return
        }
        let current = currentMonth.year * 12 + (currentMonth.month - 1)
        let months = targetMonth.index - current + 1
        guard months >= 1 else {
            monthsLeft = nil
            isOverdue = !isReached
            monthlyAmount = nil
            return
        }
        monthsLeft = months
        isOverdue = false
        monthlyAmount = isReached ? nil : (remaining / Decimal(months)).rounded(scale: 2, mode: .up)
    }

    /// The month of `now` in the person's calendar.
    public init(goal: SavingsGoal, now: Date, calendar: Calendar) {
        self.init(goal: goal, currentMonth: YearMonth(containing: now, calendar: calendar))
    }

    /// The order every list shows goals in: the ones still open first, those with a target month
    /// soonest first (overdue ones lead), then the ones without a date, and reached goals last.
    /// Ties go by name.
    public static func ordered(_ goals: [SavingsGoal], currentMonth: YearMonth) -> [Self] {
        goals.map { Self(goal: $0, currentMonth: currentMonth) }.sorted(by: precedes)
    }

    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.isReached != rhs.isReached {
            return !lhs.isReached
        }
        if !lhs.isReached {
            switch (lhs.goal.targetMonth, rhs.goal.targetMonth) {
            case let (left?, right?) where left != right: return left < right
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
        }
        let byName = lhs.goal.name.localizedCaseInsensitiveCompare(rhs.goal.name)
        if byName != .orderedSame {
            return byName == .orderedAscending
        }
        // Same name: the id keeps the order stable between loads.
        return lhs.goal.id.uuidString < rhs.goal.id.uuidString
    }
}
