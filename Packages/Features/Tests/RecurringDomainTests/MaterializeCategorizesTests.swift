import Domain
import DomainSamples
import Foundation
import Testing

/// Recording a recurring occurrence goes through the person's categorization rules (T26).
@Suite("Materialize with categorization rules")
struct MaterializeCategorizesTests {
    private typealias IDs = SampleData.IDs
    private let now = SampleData.defaultReferenceDate

    private func materialize(_ store: InMemoryStore, rules: (any CategorizationRuleRepository)?) async throws {
        try await DefaultMaterializeRecurringUseCase(
            rules: store, transactions: store, settings: store, accounts: store, cards: store, categories: store,
            categorizationRules: rules, now: { [now] in now },
        ).execute()
    }

    private func storeWithUberPass() async -> (InMemoryStore, RecurringRule) {
        let store = InMemoryStore(sample: .standard)
        let rule = RecurringRule(
            name: "Uber pass", kind: .expense, categoryID: TransactionCategory.otherExpenseID, amount: 100, currency: "NIO",
            accountID: IDs.cash, frequency: .monthly, startDate: now, autoConfirm: true,
        )
        await store.save(rule)
        return (store, rule)
    }

    @Test
    func anOccurrenceInOtherTakesTheMatchingRule() async throws {
        let (store, rule) = await storeWithUberPass()
        try await materialize(store, rules: store)
        let recorded = await store.fetchTransactions(in: nil).filter { $0.recurringID == rule.id }
        #expect(recorded.map(\.categoryID) == ["transport"])
    }

    @Test
    func withoutARuleRepositoryTheOccurrenceKeepsItsCategory() async throws {
        let (store, rule) = await storeWithUberPass()
        try await materialize(store, rules: nil)
        let recorded = await store.fetchTransactions(in: nil).filter { $0.recurringID == rule.id }
        #expect(recorded.map(\.categoryID) == [TransactionCategory.otherExpenseID])
    }
}
