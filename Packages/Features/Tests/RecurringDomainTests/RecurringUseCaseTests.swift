import Domain
import DomainSamples
import Foundation
import Testing
@testable import RecurringDomain

@Suite("Recurring use cases")
struct RecurringUseCaseTests {
    private typealias IDs = SampleData.IDs
    private let sample = SampleData.standard
    private let today = SampleData.defaultReferenceDate

    private func makeSave(_ store: InMemoryStore) -> DefaultSaveRecurringRuleUseCase {
        let now = today
        return DefaultSaveRecurringRuleUseCase(
            rules: store, accounts: store, cards: store, categories: store, settings: store,
            materialize: DefaultMaterializeRecurringUseCase(
                rules: store,
                transactions: store,
                settings: store,
                accounts: store,
                cards: store,
                categories: store,
                now: { now },
            ),
            now: { now },
        )
    }

    private func draft(start: Date, autoConfirm: Bool = false) -> RecurringRuleDraft {
        RecurringRuleDraft(
            name: "  Gym ", kind: .expense, categoryID: "health", amount: 30, currency: "USD",
            cardID: IDs.savingsDebit, startDate: start, autoConfirm: autoConfirm,
        )
    }

    @Test
    func overviewAddsUpLiveExpenseSubscriptionsInThePrincipalCurrency() async throws {
        let store = InMemoryStore(sample: sample)
        let yearly = RecurringRule(
            name: "Cloud", kind: .expense, categoryID: "subscriptions", amount: Decimal(string: "366.243") ?? 0, currency: "NIO",
            accountID: IDs.savings, frequency: .yearly, startDate: today, isSubscription: true,
        )
        let paused = RecurringRule(
            name: "Old", kind: .expense, categoryID: "subscriptions", amount: 100, currency: "USD",
            accountID: IDs.savings, frequency: .monthly, startDate: today, isSubscription: true, isPaused: true,
        )
        await store.save(yearly)
        await store.save(paused)
        let overview = try await DefaultGetRecurringOverviewUseCase(
            rules: store, accounts: store, cards: store, categories: store, transactions: store, settings: store,
        ).execute()
        // 15.99 a month, plus 366.243 NIO a year: 10 USD a year, 0.8333… a month.
        let expected = (Decimal(string: "15.99") ?? 0) + Decimal(10) / 12
        #expect(overview.subscriptionsPerMonth.currency == "USD")
        #expect(abs(NSDecimalNumber(decimal: overview.subscriptionsPerMonth.amount - expected).doubleValue) < 0.0001)
    }

    @Test
    func savingANewRuleStartingTodayRecordsItsDraftRightAway() async throws {
        let store = InMemoryStore(sample: sample)
        let saved = try await makeSave(store).execute(draft(start: today))
        #expect(saved.name == "Gym")
        #expect(saved.accountID == IDs.savings)
        #expect(saved.nextDate == today)
        let recorded = await store.fetchTransactions(in: nil).filter { $0.recurringID == saved.id }
        #expect(recorded.map(\.status) == [.planned])
        let stored = await store.fetchRecurringRules().first { $0.id == saved.id }
        #expect(try #require(stored?.nextDate) > today)
    }

    @Test
    func aNewRuleThatStartedInThePastDoesntBackfill() async throws {
        let store = InMemoryStore(sample: sample)
        let start = Calendar.current.date(byAdding: .month, value: -5, to: today) ?? today
        let saved = try await makeSave(store).execute(draft(start: start))
        #expect(saved.nextDate >= Calendar.current.startOfDay(for: today))
        #expect(await store.fetchTransactions(in: nil).filter { $0.recurringID == saved.id }.count <= 1)
    }

    @Test
    func editingTheScheduleMovesNextDateButEditingTheAmountDoesnt() async throws {
        let store = InMemoryStore(sample: sample)
        let streaming = try #require(sample.recurringRules.first { $0.id == IDs.streamingRule })
        var edit = RecurringRuleDraft(streaming)
        edit.amount = 19
        let cheaper = try await makeSave(store).execute(edit)
        #expect(cheaper.nextDate == streaming.nextDate)

        edit.interval = 2
        let rescheduled = try await makeSave(store).execute(edit)
        #expect(rescheduled.nextDate == RecurringSchedule.rescheduledNextDate(of: rescheduled, today: today, calendar: .current))
    }

    @Test
    func anInvalidRuleIsRefusedAndNothingIsSaved() async throws {
        let store = InMemoryStore(sample: sample)
        var invalid = draft(start: today)
        invalid.interval = 0
        await #expect(throws: DomainError.invalidInterval(0)) { try await makeSave(store).execute(invalid) }
        #expect(await store.fetchRecurringRules().count == sample.recurringRules.count)
    }

    @Test
    func pausingKeepsTheDateAndResumingStartsFromToday() async throws {
        let store = InMemoryStore(sample: sample)
        let now = today
        let useCase = DefaultSetRecurringRulePausedUseCase(
            rules: store,
            materialize: DefaultMaterializeRecurringUseCase(
                rules: store,
                transactions: store,
                settings: store,
                accounts: store,
                cards: store,
                categories: store,
                now: { now },
            ),
            now: { now },
        )
        let salary = try #require(sample.recurringRules.first { $0.id == IDs.salaryRule })
        try await useCase.execute(id: salary.id, isPaused: false)
        let resumed = try #require(await store.fetchRecurringRules().first { $0.id == salary.id })
        #expect(!resumed.isPaused)
        #expect(resumed.nextDate == RecurringSchedule.firstOccurrence(of: salary, onOrAfter: today, calendar: .current))

        try await useCase.execute(id: salary.id, isPaused: true)
        let paused = try #require(await store.fetchRecurringRules().first { $0.id == salary.id })
        #expect(paused.isPaused)
        #expect(paused.nextDate == resumed.nextDate)
    }
}
