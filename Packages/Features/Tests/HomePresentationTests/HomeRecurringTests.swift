import Domain
import DomainSamples
import Foundation
import RecurringDomain
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
        let rule = SampleData.IDs.streamingRule.uuidString.lowercased()
        let renewals = viewModel.reminders(now: earlier).filter { $0.kind == .renewal }
        let reminder = try #require(renewals.first { $0.id.hasPrefix("renewal:\(rule):") })
        #expect(reminder.title == "Streaming renews tomorrow")
        #expect(reminder.body.hasPrefix("$15.99 on "))
        #expect(Calendar.current.component(.hour, from: reminder.date) == LedgerNotifications.reminderHour)
        #expect(Calendar.current.isDate(reminder.date, inSameDayAs: now))
        #expect(reminder.target == ["screen": "recurring"])
    }

    private func proposalViewModel(_ store: InMemoryStore) -> HomeViewModel {
        let now = now
        let materialize = DefaultMaterializeRecurringUseCase(
            rules: store, transactions: store, settings: store, accounts: store, cards: store, categories: store, now: { now },
        )
        return HomeViewModel(
            getOverview: DefaultGetHomeOverviewUseCase(
                accounts: store, cards: store, transactions: store, categories: store, settings: store,
                recurringRules: store, now: { now },
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store),
            getPreferredName: DefaultGetPreferredNameUseCase(profile: InMemoryPasscodeStore()),
            resumeRule: DefaultSetRecurringRulePausedUseCase(rules: store, materialize: materialize, now: { now }),
            deleteRule: DefaultDeleteRecurringRuleUseCase(rules: store, transactions: store),
        )
    }

    private func proposal(in store: InMemoryStore) async -> RecurringRule {
        let rule = RecurringRule(
            name: "Gym", kind: .expense, categoryID: "health", amount: 25, currency: "USD", accountID: SampleData.IDs.savings,
            frequency: .monthly, startDate: now, isPaused: true, source: .mcp,
        )
        await store.save(rule)
        return rule
    }

    @Test
    func assistantRulesWaitOnHomeUntilConfirmedOrDiscarded() async {
        let store = InMemoryStore(sample: .standard)
        let rule = await proposal(in: store)
        let viewModel = proposalViewModel(store)
        await viewModel.load()
        // The sample's own paused salary rule was not proposed by an assistant.
        #expect(viewModel.overview?.proposedRules.map(\.id) == [rule.id])
        #expect(viewModel.proposalSubtitle(rule, hidden: false) == "$25.00 · Every month")

        await viewModel.confirmProposal(rule)
        #expect(viewModel.overview?.proposedRules.isEmpty == true)
        #expect(await store.fetchRecurringRules().first { $0.id == rule.id }?.isPaused == false)

        let other = await proposal(in: store)
        await viewModel.load()
        await viewModel.discardProposal(other)
        #expect(await !store.fetchRecurringRules().contains { $0.id == other.id })
    }
}
