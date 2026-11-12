import Domain
import DomainSamples
import FeatureTestSupport
import Foundation
import RecurringDomain
import SwiftUI
import Testing
@testable import HomeDomain
@testable import HomePresentation

/// The notifications screen empty and with a proposal and warnings, in both color schemes.
@MainActor
@Suite("Notifications snapshots")
struct NotificationsSnapshotTests {
    private let now = SampleData.defaultReferenceDate

    private func viewModel(_ store: InMemoryStore) async -> HomeViewModel {
        let now = now
        let viewModel = HomeViewModel(
            getOverview: DefaultGetHomeOverviewUseCase(
                accounts: store, cards: store, transactions: store, categories: store, settings: store,
                recurringRules: store, now: { now },
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store),
            getPreferredName: DefaultGetPreferredNameUseCase(profile: InMemoryPasscodeStore()),
            listNotificationStates: DefaultListNotificationStatesUseCase(repository: store),
            changeNotifications: DefaultChangeNotificationsUseCase(repository: store),
        )
        await viewModel.load()
        return viewModel
    }

    private func emptyStore() -> InMemoryStore {
        // One cash account and nothing else: no card, subscription, loan or budget to warn about.
        let sample = SampleData.standard
        return InMemoryStore(
            accounts: sample.accounts.filter { $0.kind == .cash },
            categories: sample.categories,
            settings: sample.settings,
        )
    }

    private func screen(_ viewModel: HomeViewModel) -> some View {
        NotificationsView(viewModel: viewModel, onBack: {}, onOpen: { _ in }, now: now)
    }

    private func populatedStore() async -> InMemoryStore {
        let store = InMemoryStore(sample: .standard)
        await store.save(RecurringRule(
            name: "Gym", kind: .expense, categoryID: "health", amount: 25, currency: "USD", accountID: SampleData.IDs.savings,
            frequency: .monthly, startDate: now, isPaused: true, source: .mcp,
        ))
        return store
    }

    @Test
    func emptyDark() async {
        await assertScreenSnapshot(of: screen(viewModel(emptyStore())), colorScheme: .dark)
    }

    @Test
    func emptyLight() async {
        await assertScreenSnapshot(of: screen(viewModel(emptyStore())), colorScheme: .light)
    }

    /// The proposal on top, then the days, with the oldest row already read and the undo toast up.
    private func populatedViewModel() async -> HomeViewModel {
        let viewModel = await viewModel(populatedStore())
        if let read = viewModel.inbox(now: now, calendar: viewModel.calendar).last(where: { $0.kind != .proposal }) {
            await viewModel.toggleRead(read)
        }
        if let deleted = viewModel.inbox(now: now, calendar: viewModel.calendar).first(where: { $0.kind == .budget }) {
            await viewModel.delete(deleted)
        }
        return viewModel
    }

    @Test
    func withDataDark() async {
        await assertScreenSnapshot(of: screen(populatedViewModel()), colorScheme: .dark)
    }

    @Test
    func withDataLight() async {
        await assertScreenSnapshot(of: screen(populatedViewModel()), colorScheme: .light)
    }
}
