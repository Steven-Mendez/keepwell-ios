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
    func theCardsCountWhatTheirTotalsAddUp() async throws {
        let viewModel = await loaded()
        let overview = try #require(viewModel.overview)
        // The sample: Juan owes part of a dinner; the motorbike loan and Ana's tickets are owed.
        #expect(viewModel.youOweTitle(overview.debts) == "2 debts to pay")
        #expect(viewModel.owedToYouTitle(overview.debts) == "1 person owes you")
        let count = overview.recurring.subscriptionCount
        #expect(count > 0)
        #expect(viewModel
            .subscriptionsCaption(overview.recurring) == (count == 1 ? "Per month · 1 subscription" : "Per month · \(count) subscriptions"))
    }

    /// T10/T13: a subscription in a currency the rate can't convert stays out of the total and of
    /// the count, and the card says so, as the Recurring screen does.
    @Test
    func aSubscriptionTheTotalLeavesOutIsNamedApart() async throws {
        let before = try #require(await loaded().overview?.recurring)
        let store = InMemoryStore(sample: .standard)
        let streaming = try #require(SampleData.standard.recurringRules.first { $0.id == SampleData.IDs.streamingRule })
        await store.save(RecurringRule(
            name: "Music", kind: .expense, categoryID: streaming.categoryID, amount: 9, currency: "EUR",
            accountID: streaming.accountID, frequency: .monthly, startDate: streaming.startDate,
            nextDate: streaming.nextDate, isSubscription: true,
        ))
        let viewModel = await loaded(store)
        let recurring = try #require(viewModel.overview?.recurring)
        #expect(recurring.subscriptionsPerMonth == before.subscriptionsPerMonth)
        #expect(recurring.subscriptionCount == before.subscriptionCount)
        #expect(viewModel.subscriptionsCaption(recurring) == viewModel.subscriptionsCaption(before))
        #expect(viewModel.excludedSubscriptionLines(recurring) == ["Not including 1 in EUR"])
        #expect(viewModel.excludedSubscriptionLines(before).isEmpty)
    }

    @Test
    func withoutCountsTheCardsKeepTheirTitles() {
        let viewModel = PlanViewModel(getOverview: PlanOverviewStub())
        let debts = PlanOverview.Debts(totals: DebtTotals(loans: [], debts: []), nextLoan: nil, hasDebts: false)
        let recurring = PlanOverview.Recurring(subscriptionsPerMonth: Money(0, "USD"), next: nil, hasRules: true)
        #expect(viewModel.youOweTitle(debts) == "You owe")
        #expect(viewModel.owedToYouTitle(debts) == "Owed to you")
        #expect(viewModel.subscriptionsCaption(recurring) == "Subscriptions per month")
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
