import Domain
import DomainSamples
import Foundation
import Testing
@testable import HomeDomain
@testable import HomePresentation

@MainActor
@Suite("Home goals")
struct HomeGoalsTests {
    private let now = SampleData.defaultReferenceDate

    private func loadedViewModel(_ store: InMemoryStore = InMemoryStore(sample: .standard)) async -> HomeViewModel {
        let viewModel = HomeViewModel(
            getOverview: DefaultGetHomeOverviewUseCase(
                accounts: store, cards: store, transactions: store, categories: store, settings: store,
                savingsGoals: store, now: { [now] in now },
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store),
            getPreferredName: DefaultGetPreferredNameUseCase(profile: InMemoryPasscodeStore()),
        )
        await viewModel.load()
        return viewModel
    }

    @Test
    func theCardPreviewsTheSoonestOpenGoal() async throws {
        let viewModel = await loadedViewModel()
        let top = try #require(viewModel.overview?.goals.first)
        #expect(top.goal.id == SampleData.IDs.tripGoal)
        #expect(viewModel.goalAmounts(top, hidden: false) == "C$4,500.00 of C$15,000.00")
        #expect(viewModel.goalAmounts(top, hidden: true) == "•••• of ••••")
        #expect(viewModel.goalBarFraction(top) == 0.3)
    }

    @Test
    func withoutARepositoryThereAreNoGoals() async {
        let store = InMemoryStore(sample: .standard)
        let viewModel = HomeViewModel(
            getOverview: DefaultGetHomeOverviewUseCase(
                accounts: store, cards: store, transactions: store, categories: store, settings: store, now: { [now] in now },
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store),
            getPreferredName: DefaultGetPreferredNameUseCase(profile: InMemoryPasscodeStore()),
        )
        await viewModel.load()
        #expect(viewModel.overview?.goals.isEmpty == true)
    }
}
