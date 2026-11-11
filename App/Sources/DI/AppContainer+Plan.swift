import DebtsDomain
import GoalsDomain
import PlanDomain
import PlanPresentation
import RecurringDomain

// MARK: - Plan

extension AppContainer {
    func makePlanViewModel() -> PlanViewModel {
        PlanViewModel(
            getOverview: DefaultGetPlanOverviewUseCase(
                recurring: RecurringPlanSource(makeGetRecurringOverview()),
                goals: GoalsPlanSource(DefaultGetSavingsGoalsUseCase(goals: store, settings: store)),
                debts: DebtsPlanSource(DefaultGetDebtsUseCase(loans: store, debts: store, settings: store)),
            ),
        )
    }
}
