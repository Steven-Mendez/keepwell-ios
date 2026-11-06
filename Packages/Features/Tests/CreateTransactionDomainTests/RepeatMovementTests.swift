import Domain
import DomainSamples
import Foundation
import Testing
@testable import CreateTransactionDomain

@Suite("Repeat a new movement")
struct RepeatMovementTests {
    private let store = InMemoryStore(sample: .standard)
    private let now = SampleData.defaultReferenceDate

    private func useCase(repeats: Bool = true) -> DefaultSaveTransactionUseCase {
        let context = DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: store, now: { [now] in now },
        )
        return DefaultSaveTransactionUseCase(context: context, transactions: store, recurringRules: repeats ? store : nil)
    }

    private func draft(category: String = Subscriptions.categoryID, repeating frequency: RecurringFrequency?) -> TransactionDraft {
        TransactionDraft(
            kind: .expense, amount: 12, currency: "USD", categoryID: category, source: .card(SampleData.IDs.mastercardHolder),
            description: "Music", date: now, repeatFrequency: frequency,
        )
    }

    @Test
    func repeatingSavesARuleFromTheMovementAndTheMovementNamesIt() async throws {
        let saved = try await useCase().execute(draft(repeating: .monthly))
        let rule = try #require(await store.fetchRecurringRules().first { $0.id == saved.transaction.recurringID })
        #expect(rule.name == "Music")
        #expect(rule.frequency == .monthly)
        #expect(rule.interval == 1)
        #expect(rule.startDate == now)
        #expect(rule.nextDate == Calendar.current.date(byAdding: .month, value: 1, to: now))
        #expect(rule.isSubscription)
        #expect(!rule.autoConfirm)
        #expect(rule.accountID == SampleData.IDs.mastercard)
        #expect(rule.cardID == SampleData.IDs.mastercardHolder)
    }

    @Test
    func onlyTheSubscriptionsCategoryMakesItASubscription() async throws {
        let saved = try await useCase().execute(draft(category: "restaurants", repeating: .weekly))
        let rule = try #require(await store.fetchRecurringRules().first { $0.id == saved.transaction.recurringID })
        #expect(!rule.isSubscription)
        #expect(rule.nextDate == Calendar.current.date(byAdding: .day, value: 7, to: now))
    }

    @Test
    func withoutRepeatNoRuleIsSaved() async throws {
        let before = await store.fetchRecurringRules().count
        let saved = try await useCase().execute(draft(repeating: nil))
        #expect(saved.transaction.recurringID == nil)
        #expect(await store.fetchRecurringRules().count == before)
        let ignored = try await useCase(repeats: false).execute(draft(repeating: .yearly))
        #expect(ignored.transaction.recurringID == nil)
    }
}
