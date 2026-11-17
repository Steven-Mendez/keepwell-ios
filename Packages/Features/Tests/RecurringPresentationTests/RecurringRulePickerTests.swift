import Domain
import DomainSamples
import FeatureTestSupport
import Foundation
import Testing
@testable import RecurringPresentation

/// "Link to a recurring", opened from a movement: which rules it offers and what choosing one does.
@Suite("Recurring rule picker")
@MainActor
struct RecurringRulePickerTests {
    private typealias IDs = SampleData.IDs
    private let today = SampleData.defaultReferenceDate

    private func charge(description: String = "STREAMING.COM", amount: String = "15.99") -> Domain.Transaction {
        Domain.Transaction(
            date: Calendar.current.date(byAdding: .day, value: -3, to: today) ?? today,
            status: .confirmed,
            description: description,
            kind: .expense,
            categoryID: "subscriptions",
            amount: Decimal(string: amount) ?? 0,
            currency: "USD",
            accountID: IDs.mastercard,
            cardID: IDs.mastercardHolder,
            exchangeRate: SampleData.standard.settings.currencies.exchangeRate,
        )
    }

    @Test
    func offersOnlyRulesOfTheMovementsKindWithTheMatchingOneFirst() async {
        let store = InMemoryStore(sample: .standard)
        let manual = charge()
        await store.save(manual)
        let model = RecurringPreview.pickerViewModel(transaction: manual, store: store)
        await model.load()

        #expect(!model.rules.isEmpty)
        #expect(model.rules.allSatisfy { $0.kind == .expense })
        #expect(model.rules.first?.id == IDs.streamingRule)
    }

    @Test
    func choosingARuleLinksTheMovementWithoutMovingTheSchedule() async throws {
        let store = InMemoryStore(sample: .standard)
        let manual = charge()
        await store.save(manual)
        let before = try #require(await store.fetchRecurringRules().first { $0.id == IDs.streamingRule })
        let model = RecurringPreview.pickerViewModel(transaction: manual, store: store)
        await model.load()

        let rule = try #require(model.rules.first { $0.id == IDs.streamingRule })
        #expect(await model.link(to: rule))

        let stored = try #require(await store.fetchTransactions(in: nil).first { $0.id == manual.id })
        #expect(stored.recurringID == IDs.streamingRule)
        let after = try #require(await store.fetchRecurringRules().first { $0.id == IDs.streamingRule })
        #expect(after.nextDate == before.nextDate)
    }
}
