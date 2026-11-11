import DebtsDomain
import DomainSamples
import Foundation
import GoalsDomain
import PlanDomain
import RecurringDomain

/// The hub wired to the sample data in memory, for `#Preview` and tests.
@MainActor
public enum PlanPreview {
    public static func viewModel(
        store: InMemoryStore = InMemoryStore(sample: .standard),
        now: Date = SampleData.defaultReferenceDate,
    ) -> PlanViewModel {
        PlanViewModel(
            getOverview: DefaultGetPlanOverviewUseCase(
                recurring: RecurringPlanSource(DefaultGetRecurringOverviewUseCase(
                    rules: store, accounts: store, cards: store, categories: store, transactions: store, settings: store,
                )),
                goals: GoalsPlanSource(DefaultGetSavingsGoalsUseCase(goals: store, settings: store, now: { now })),
                debts: DebtsPlanSource(DefaultGetDebtsUseCase(loans: store, debts: store, settings: store, now: { now })),
                now: { now },
            ),
            now: { now },
        )
    }
}
