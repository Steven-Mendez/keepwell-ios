// The hub only composes its sibling features' use cases, so unlike other Domain code it imports them.
// swiftlint:disable domain_imports_foundation_only
import DebtsDomain
import Domain
import Foundation
import GoalsDomain
import RecurringDomain

// swiftlint:enable domain_imports_foundation_only

public protocol GetPlanOverviewUseCase: Sendable {
    func execute() async throws(DomainError) -> PlanOverview
}

/// Composes the three planning screens' own use cases, so the hub always shows the same figures
/// as the screens it leads to.
public struct DefaultGetPlanOverviewUseCase: GetPlanOverviewUseCase {
    /// How far ahead the next recurring movement is looked for.
    static let lookaheadDays = 366

    private let recurring: any GetRecurringOverviewUseCase
    private let goals: any GetSavingsGoalsUseCase
    private let debts: any GetDebtsUseCase
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        recurring: any GetRecurringOverviewUseCase,
        goals: any GetSavingsGoalsUseCase,
        debts: any GetDebtsUseCase,
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
        let recurringOverview = try await recurring.execute()
        let goalsOverview = try await goals.execute()
        let debtsOverview = try await debts.execute()
        let next = RecurringSchedule.upcoming(
            recurringOverview.rules, from: now(), days: Self.lookaheadDays, calendar: calendar,
        ).min { $0.date < $1.date }
        return PlanOverview(
            recurring: .init(
                subscriptionsPerMonth: recurringOverview.subscriptionsPerMonth,
                next: next,
                hasRules: !recurringOverview.rules.isEmpty,
            ),
            goals: .init(top: goalsOverview.goals.first, count: goalsOverview.goals.count),
            debts: .init(
                totals: debtsOverview.totals,
                nextLoan: debtsOverview.loans.first { $0.next != nil },
                hasDebts: !debtsOverview.loans.isEmpty || !debtsOverview.debts.isEmpty,
            ),
        )
    }
}
