import Domain
import DomainSamples
import Foundation
import Testing
@testable import TransactionsDomain

@Suite("Movements recorded by a rule")
struct RecurringListTests {
    @Test
    func aMovementNamesItsLiveRuleOnly() async throws {
        let sample = SampleData.standard
        let store = InMemoryStore(sample: sample)
        let rule = try #require(sample.recurringRules.first)
        let movement = RecurringSchedule.movement(from: rule, on: rule.nextDate, exchangeRate: sample.settings.currencies.exchangeRate)
        await store.save(movement)
        let useCase = DefaultGetTransactionListUseCase(
            transactions: store, accounts: store, cards: store, categories: store, settings: store, recurringRules: store,
        )
        #expect(try await useCase.execute().recurringRule(of: movement) == rule)

        try await store.deleteRecurringRule(id: rule.id)
        #expect(try await useCase.execute().recurringRule(of: movement) == nil)
    }
}
