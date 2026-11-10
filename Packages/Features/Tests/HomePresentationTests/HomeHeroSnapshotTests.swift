import Domain
import DomainSamples
import FeatureTestSupport
import Foundation
import SwiftUI
import Testing
@testable import HomeDomain
@testable import HomePresentation

/// The hero when net worth leaves a currency out: the note sits under the amount.
@MainActor
@Suite("Home hero snapshots")
struct HomeHeroSnapshotTests {
    private let now = SampleData.defaultReferenceDate
    /// The greeting reads the hour in this calendar: fixed, so the snapshot is the same on any machine.
    private static let gmt: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    private func loadedViewModel() async throws -> HomeViewModel {
        let store = InMemoryStore(sample: .standard)
        try await store.save(Account(
            id: UUID(), name: "Abroad", kind: .cash, openingBalances: [Money(50, "CHF"), Money(20, "EUR")],
            openingDate: now.addingTimeInterval(-86400),
        ))
        let viewModel = HomeViewModel(
            getOverview: DefaultGetHomeOverviewUseCase(
                accounts: store, cards: store, transactions: store, categories: store, settings: store, now: { [now] in now },
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store),
            getPreferredName: DefaultGetPreferredNameUseCase(profile: InMemoryPasscodeStore(name: "Steven")),
            calendar: Self.gmt,
        )
        await viewModel.load()
        return viewModel
    }

    private func hero(_ viewModel: HomeViewModel) -> some View {
        HomeHero(
            viewModel: viewModel,
            actions: HomeView.Actions(
                search: {}, summary: {}, settings: {}, accounts: {}, newMovement: { _ in }, payCard: {}, allPlanned: {},
                allTransactions: {},
            ),
            hidesBalances: .constant(false),
            fixedDate: now,
        )
    }

    @Test
    func theNoteNamesTheCurrenciesLeftOut() async throws {
        let viewModel = try await loadedViewModel()
        let overview = try #require(viewModel.overview)
        #expect(overview.netWorthExcluded == ["CHF", "EUR"])
        let note = try #require(viewModel.balancePages(overview).first?.note)
        #expect(note == "Doesn't include balances in CHF, EUR")
        #expect(viewModel.balancePages(overview).dropFirst().allSatisfy { $0.note == nil })
    }

    @Test
    func heroWithTheNoteDark() async throws {
        try await assertScreenSnapshot(of: hero(loadedViewModel()), height: 460, colorScheme: .dark)
    }

    @Test
    func heroWithTheNoteLight() async throws {
        try await assertScreenSnapshot(of: hero(loadedViewModel()), height: 460, colorScheme: .light)
    }
}
