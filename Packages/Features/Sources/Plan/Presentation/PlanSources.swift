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

    public func load() async throws(DomainError) -> (rules: [RecurringRule], subscriptionsPerMonth: Money) {
        let overview = try await getOverview.execute()
        return (overview.rules, overview.subscriptionsPerMonth)
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
