import Domain
import DomainSamples
import FeatureTestSupport
import Foundation
import PlanDomain
import SwiftUI
import Testing
@testable import PlanPresentation

@MainActor
@Suite("Plan")
struct PlanViewModelTests {
    private func loaded(_ store: InMemoryStore = InMemoryStore(sample: .standard)) async -> PlanViewModel {
        let viewModel = PlanPreview.viewModel(store: store)
        await viewModel.load()
        return viewModel
    }

    @Test
    func wordsTheCardsLikeTheScreensTheyOpen() async throws {
        let viewModel = await loaded()
        let overview = try #require(viewModel.overview)
        #expect(viewModel.nextRecurringLine(overview.recurring)?.hasPrefix("Next: ") == true)
        let top = try #require(overview.goals.top)
        #expect(viewModel.goalAmounts(top, hidden: false) == "C$4,500.00 of C$15,000.00")
        #expect(viewModel.goalPercent(top) == "30%")
        #expect(viewModel.goalCount(overview.goals) == "\(overview.goals.count) goals")
        #expect(viewModel.debtTotal(overview.debts.totals.youOwe, hidden: false) == "C$55,000.00 · $40.00")
        #expect(viewModel.nextInstallmentLine(overview.debts, hidden: false)?.hasPrefix("Next: 3/12 on ") == true)
    }

    @Test
    func hidingAmountsMasksEveryOne() async throws {
        let viewModel = await loaded()
        let overview = try #require(viewModel.overview)
        let top = try #require(overview.goals.top)
        #expect(viewModel.subscriptionsPerMonth(overview.recurring, hidden: true) == "••••")
        #expect(viewModel.goalAmounts(top, hidden: true) == "•••• of ••••")
        #expect(viewModel.debtTotal(overview.debts.totals.owedToYou, hidden: true) == "••••")
        #expect(viewModel.nextInstallmentLine(overview.debts, hidden: true)?.hasSuffix("· ••••") == true)
    }

    @Test
    func noDebtsReadNothing() {
        let viewModel = PlanViewModel(getOverview: PlanOverviewStub())
        #expect(viewModel.debtTotal([], hidden: false) == "Nothing")
    }

    @Test
    func planHub() async {
        let viewModel = await loaded()
        assertScreenSnapshot(of: PlanView(viewModel: viewModel, onOpenRecurring: {}, onOpenGoals: {}, onOpenDebts: {}))
    }

    @Test
    func emptyPlanHub() async throws {
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
        let viewModel = await loaded(store)
        assertScreenSnapshot(of: PlanView(viewModel: viewModel, onOpenRecurring: {}, onOpenGoals: {}, onOpenDebts: {}))
    }
}

private struct PlanOverviewStub: GetPlanOverviewUseCase {
    func execute() async throws(DomainError) -> PlanOverview {
        throw .notFound(UUID())
    }
}
