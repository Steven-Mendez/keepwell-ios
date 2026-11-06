import Domain
import DomainSamples
import Foundation
import GoalsDomain
import SwiftUI

/// Screens wired to the sample data in memory, for `#Preview` and tests.
@MainActor
public enum GoalsPreview {
    public static func listViewModel(
        store: InMemoryStore = InMemoryStore(sample: .standard),
        now: Date = SampleData.defaultReferenceDate,
    ) -> GoalsViewModel {
        GoalsViewModel(
            getGoals: DefaultGetSavingsGoalsUseCase(goals: store, settings: store, now: { now }),
            save: DefaultSaveSavingsGoalUseCase(goals: store, settings: store),
            moveMoney: DefaultMoveSavingsGoalMoneyUseCase(goals: store),
            delete: DefaultDeleteSavingsGoalUseCase(goals: store),
        )
    }

    static func list() -> some View {
        GoalsView(viewModel: listViewModel(), onBack: {})
    }
}
