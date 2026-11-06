import DomainSamples
import Foundation
import Testing
@testable import Domain

@Suite("Recurring actions")
struct RecurringActionsTests {
    private typealias IDs = SampleData.IDs
    private let sample = SampleData.standard

    @Test
    func materializingRecordsDueOccurrencesAtTheCurrentRateInOneGo() async throws {
        let store = InMemoryStore(sample: sample)
        // The sample's streaming rule is due on the 23rd; run it on the 24th.
        let today = Fixtures.calendar.date(byAdding: .day, value: 2, to: SampleData.defaultReferenceDate) ?? .now
        let useCase = DefaultMaterializeRecurringUseCase(
            rules: store, transactions: store, settings: store, calendar: .current, now: { today },
        )
        let recorded = try await useCase.execute()
        let movements = await store.fetchTransactions(in: nil).filter { $0.recurringID == IDs.streamingRule }
        #expect(recorded >= 1)
        #expect(movements.count == 1)
        #expect(movements.first?.status == .confirmed)
        #expect(movements.first?.exchangeRate == sample.settings.currencies.exchangeRate)
        let streaming = await store.fetchRecurringRules().first { $0.id == IDs.streamingRule }
        #expect(try #require(streaming?.nextDate) > today)

        #expect(try await useCase.execute() == 0)
    }

    @Test
    func deletingARuleRemovesItsDraftsButKeepsWhatWasConfirmed() async throws {
        let store = InMemoryStore(sample: sample)
        let rule = try #require(sample.recurringRules.first { $0.id == IDs.rentRule })
        let rate = sample.settings.currencies.exchangeRate
        let confirmed = RecurringSchedule.movement(from: rule, on: rule.startDate, exchangeRate: rate).confirmed()
        let draft = RecurringSchedule.movement(from: rule, on: rule.nextDate, exchangeRate: rate)
        await store.saveMaterialized(transactions: [confirmed, draft], rules: [])

        try await DefaultDeleteRecurringRuleUseCase(rules: store, transactions: store).execute(id: rule.id)

        #expect(await !store.fetchRecurringRules().contains { $0.id == rule.id })
        let left = await store.fetchTransactions(in: nil).filter { $0.recurringID == rule.id }
        #expect(left.map(\.id) == [confirmed.id])
    }

    @Test
    func deletingAnAccountDeletesTheRulesThatPayFromItOrIntoIt() async throws {
        let store = InMemoryStore(sample: sample)
        try await DefaultDeleteAccountUseCase(accounts: store, cards: store, transactions: store, recurringRules: store)
            .execute(accountID: IDs.cash)
        let left = await store.fetchRecurringRules().map(\.id)
        #expect(!left.contains(IDs.cashRule))
        #expect(left.contains(IDs.rentRule))
    }

    @Test
    func mergedCardsTakeTheirRulesAlong() async throws {
        let store = InMemoryStore(sample: sample)
        let spare = try Card(accountID: IDs.savings, kind: .debit, lastFour: "4444")
        await store.save(spare)
        let rule = RecurringRule(
            name: "Gym", kind: .expense, categoryID: "health", amount: 10, currency: "USD", accountID: IDs.savings,
            cardID: spare.id, frequency: .monthly, startDate: .now,
        )
        await store.save(rule)
        try await DefaultNormalizeBankCardsUseCase(accounts: store, cards: store, transactions: store, recurringRules: store).execute()
        #expect(await store.fetchRecurringRules().first { $0.id == rule.id }?.cardID == IDs.savingsDebit)
    }
}
