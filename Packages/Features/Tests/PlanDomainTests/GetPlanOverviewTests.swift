import DebtsDomain
import Domain
import DomainSamples
import Foundation
import GoalsDomain
import RecurringDomain
import Testing
@testable import PlanDomain

@Suite("Plan overview")
struct GetPlanOverviewTests {
    private let now = SampleData.defaultReferenceDate

    private func useCase(_ store: InMemoryStore) -> DefaultGetPlanOverviewUseCase {
        DefaultGetPlanOverviewUseCase(
            recurring: DefaultGetRecurringOverviewUseCase(
                rules: store, accounts: store, cards: store, categories: store, transactions: store, settings: store,
            ),
            goals: DefaultGetSavingsGoalsUseCase(goals: store, settings: store, now: { [now] in now }),
            debts: DefaultGetDebtsUseCase(loans: store, debts: store, settings: store, now: { [now] in now }),
            now: { [now] in now },
        )
    }

    @Test
    func summarizesTheThreeScreensWithTheirOwnFigures() async throws {
        let store = InMemoryStore(sample: .standard)
        let overview = try await useCase(store).execute()
        let recurring = try await DefaultGetRecurringOverviewUseCase(
            rules: store, accounts: store, cards: store, categories: store, transactions: store, settings: store,
        ).execute()
        #expect(overview.recurring.hasRules)
        #expect(overview.recurring.subscriptionsPerMonth == recurring.subscriptionsPerMonth)
        let next = try #require(overview.recurring.next)
        #expect(next.date >= Calendar.current.startOfDay(for: now))
        let goals = try await DefaultGetSavingsGoalsUseCase(goals: store, settings: store, now: { [now] in now }).execute()
        #expect(overview.goals.top == goals.goals.first)
        #expect(overview.goals.count == goals.goals.count)
        #expect(overview.debts.hasDebts)
        #expect(overview.debts.nextLoan?.next?.number == 3)
    }

    @Test
    func nothingPlannedYieldsEmptySummaries() async throws {
        let store = InMemoryStore(sample: .standard)
        for rule in SampleData.standard.recurringRules {
            try await store.deleteRecurringRule(id: rule.id)
        }
        for goal in SampleData.standard.savingsGoals {
            try await store.deleteSavingsGoal(id: goal.id)
        }
        for loan in SampleData.standard.loans {
            try await store.deleteLoan(id: loan.id)
        }
        for debt in SampleData.standard.personalDebts {
            try await store.deletePersonalDebt(id: debt.id)
        }
        let overview = try await useCase(store).execute()
        #expect(!overview.recurring.hasRules)
        #expect(overview.recurring.next == nil)
        #expect(overview.goals.top == nil)
        #expect(!overview.debts.hasDebts)
        #expect(overview.debts.nextLoan == nil)
    }
}
