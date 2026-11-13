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
        let subscriptions = recurring.rules.count {
            $0.isSubscription && $0.kind == .expense && RecurringSchedule.isActive($0, calendar: calendar)
        }
        // Counted the way `DebtTotals` picks what it adds up.
        let openDebts = debts.debts.filter { !$0.isSettled && $0.remaining > 0 }
        let people = Set(openDebts.filter { $0.direction == .theyOweMe }
            .map { $0.person.trimmingCharacters(in: .whitespaces).lowercased() })
        return PlanOverview(
            recurring: .init(
                subscriptionsPerMonth: recurring.subscriptionsPerMonth,
                subscriptionCount: subscriptions,
                next: next,
                hasRules: !recurring.rules.isEmpty,
            ),
            goals: .init(top: goals.first, count: goals.count),
            debts: .init(
                totals: debts.totals,
                youOweCount: debts.loans.count { !$0.loan.isPaidOff } + openDebts.count { $0.direction == .iOwe },
                peopleOwingCount: people.count,
                nextLoan: debts.loans.first { $0.next != nil },
                hasDebts: !debts.loans.isEmpty || !debts.debts.isEmpty,
            ),
        )
    }
}
