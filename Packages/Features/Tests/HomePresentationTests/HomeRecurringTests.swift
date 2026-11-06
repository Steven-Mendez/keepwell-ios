import Domain
import DomainSamples
import Foundation
import Testing
@testable import HomeDomain
@testable import HomePresentation

@MainActor
@Suite("Home recurring")
struct HomeRecurringTests {
    private let now = SampleData.defaultReferenceDate

    private func loadedViewModel() async -> HomeViewModel {
        let store = InMemoryStore(sample: .standard)
        let viewModel = HomeViewModel(
            getOverview: DefaultGetHomeOverviewUseCase(
                accounts: store, cards: store, transactions: store, categories: store, settings: store,
                recurringRules: store, now: { [now] in now },
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store),
            getPreferredName: DefaultGetPreferredNameUseCase(profile: InMemoryPasscodeStore()),
        )
        await viewModel.load()
        return viewModel
    }

    @Test
    func upcomingShowsTheNextWeekWithoutPausedRules() async throws {
        let viewModel = await loadedViewModel()
        let overview = try #require(viewModel.overview)
        let upcoming = viewModel.upcomingPreview(overview, now: now)
        // Streaming tomorrow and the cash top-up in two days; the salary is paused, rent is next month.
        #expect(upcoming.map(\.rule.id) == [SampleData.IDs.streamingRule, SampleData.IDs.cashRule])
        #expect(viewModel.upcomingSubtitle(upcoming[0], now: now).hasPrefix("Tomorrow · "))
        #expect(viewModel.upcomingAmount(upcoming[0], hidden: false) == "−$15.99")
        #expect(viewModel.upcomingAmount(upcoming[0], hidden: true) == "••••")
    }

    @Test
    func aSubscriptionIsRemindedTheMorningBeforeItRenews() async throws {
        let viewModel = await loadedViewModel()
        // Just before the sample's day starts, so the morning reminder for tomorrow's renewal is ahead.
        let earlier = Calendar.current.startOfDay(for: now).addingTimeInterval(-60)
        let renewals = viewModel.reminders(now: earlier).filter { $0.kind == .subscription(SampleData.IDs.streamingRule) }
        let reminder = try #require(renewals.first)
        #expect(reminder.title == "Streaming renews tomorrow")
        #expect(reminder.body.hasPrefix("$15.99 on "))
        #expect(Calendar.current.component(.hour, from: reminder.date) == HomeViewModel.reminderHour)
        #expect(Calendar.current.isDate(reminder.date, inSameDayAs: now))
        #expect(viewModel.reminders(now: earlier).allSatisfy { reminder in
            if case let .subscription(id) = reminder.kind {
                id == SampleData.IDs.streamingRule
            } else {
                true
            }
        })
    }
}
