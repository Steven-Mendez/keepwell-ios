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
                recurring: makeGetRecurringOverview(),
                goals: DefaultGetSavingsGoalsUseCase(goals: store, settings: store),
                debts: DefaultGetDebtsUseCase(loans: store, debts: store, settings: store),
            ),
        )
    }
}
