import GoalsDomain
import GoalsPresentation

// MARK: - Goals

extension AppContainer {
    func makeGoalsViewModel() -> GoalsViewModel {
        GoalsViewModel(
            getGoals: DefaultGetSavingsGoalsUseCase(goals: store, settings: store),
            save: DefaultSaveSavingsGoalUseCase(goals: store, settings: store),
            moveMoney: DefaultMoveSavingsGoalMoneyUseCase(goals: store),
            delete: DefaultDeleteSavingsGoalUseCase(goals: store),
        )
    }
}
