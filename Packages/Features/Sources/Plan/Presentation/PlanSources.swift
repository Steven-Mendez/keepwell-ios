import DebtsDomain
import Domain
import GoalsDomain
import PlanDomain
import RecurringDomain

/// Adapters from the Recurring, Goals and Debts use cases to what the hub reads, shared by the app,
/// previews and tests.
public struct RecurringPlanSource: PlanRecurringSource {
    private let getOverview: any GetRecurringOverviewUseCase

    public init(_ getOverview: any GetRecurringOverviewUseCase) {
        self.getOverview = getOverview
    }

    /// The Recurring screen's own total and exclusions (`RecurringOverview.monthlyTotal`), so the
    /// hub never counts differently from the screen it opens.
    public func load() async throws(DomainError) -> PlanRecurringFigures {
        let overview = try await getOverview.execute()
        return PlanRecurringFigures(
            rules: overview.rules,
            subscriptionsPerMonth: overview.subscriptionsPerMonth,
            excluded: overview.excludedSubscriptions.map { .init(currency: $0.currency, count: $0.count) },
        )
    }
}

public struct GoalsPlanSource: PlanGoalsSource {
    private let getGoals: any GetSavingsGoalsUseCase

    public init(_ getGoals: any GetSavingsGoalsUseCase) {
        self.getGoals = getGoals
    }

    public func load() async throws(DomainError) -> [SavingsGoalProgress] {
        try await getGoals.execute().goals
    }
}

public struct DebtsPlanSource: PlanDebtsSource {
    private let getDebts: any GetDebtsUseCase

    public init(_ getDebts: any GetDebtsUseCase) {
        self.getDebts = getDebts
    }

    public func load() async throws(DomainError) -> (loans: [LoanProgress], debts: [PersonalDebt], totals: DebtTotals) {
        let overview = try await getDebts.execute()
        return (overview.loans, overview.debts, overview.totals)
    }
}
