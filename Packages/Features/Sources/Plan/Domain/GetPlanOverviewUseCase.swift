import Domain
import Foundation

/// What the hub needs from Recurring, Goals and Debts. Each feature's own use case answers these
/// through an adapter, so the hub never depends on a sibling feature's Domain.
public protocol PlanRecurringSource: Sendable {
    func load() async throws(DomainError) -> (rules: [RecurringRule], subscriptionsPerMonth: Money)
}

public protocol PlanGoalsSource: Sendable {
    /// In list order.
    func load() async throws(DomainError) -> [SavingsGoalProgress]
}

public protocol PlanDebtsSource: Sendable {
    func load() async throws(DomainError) -> (loans: [LoanProgress], debts: [PersonalDebt], totals: DebtTotals)
}

public protocol GetPlanOverviewUseCase: Sendable {
    func execute() async throws(DomainError) -> PlanOverview
}

/// Composes the three planning screens' figures, so the hub always shows the same ones as the
/// screens it leads to.
public struct DefaultGetPlanOverviewUseCase: GetPlanOverviewUseCase {
    /// How far ahead the next recurring movement is looked for.
    static let lookaheadDays = 366

    private let recurring: any PlanRecurringSource
    private let goals: any PlanGoalsSource
    private let debts: any PlanDebtsSource
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        recurring: any PlanRecurringSource,
        goals: any PlanGoalsSource,
        debts: any PlanDebtsSource,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now },
    ) {
        self.recurring = recurring
        self.goals = goals
        self.debts = debts
        self.calendar = calendar
        self.now = now
    }

    public func execute() async throws(DomainError) -> PlanOverview {
        let recurring = try await recurring.load()
        let goals = try await goals.load()
        let debts = try await debts.load()
        let next = RecurringSchedule.upcoming(recurring.rules, from: now(), days: Self.lookaheadDays, calendar: calendar)
            .min { $0.date < $1.date }
        return PlanOverview(
            recurring: .init(subscriptionsPerMonth: recurring.subscriptionsPerMonth, next: next, hasRules: !recurring.rules.isEmpty),
            goals: .init(top: goals.first, count: goals.count),
            debts: .init(
                totals: debts.totals,
                nextLoan: debts.loans.first { $0.next != nil },
                hasDebts: !debts.loans.isEmpty || !debts.debts.isEmpty,
            ),
        )
    }
}
