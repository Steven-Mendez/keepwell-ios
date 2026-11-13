import Domain
import DomainSamples
import FeatureTestSupport
import Foundation
import SwiftUI
import Testing
@testable import RecurringPresentation

@Suite("Recurring snapshots")
@MainActor
struct RecurringSnapshotTests {
    @Test
    func recurringList() async {
        let viewModel = RecurringPreview.listViewModel()
        await viewModel.load()
        assertScreenSnapshot(
            of: RecurringView(viewModel: viewModel, onBack: {}, onAdd: {}, onAddSubscription: {}, onOpen: { _ in }),
            height: 900,
        )
    }

    /// Drafts waiting on Rent (three days late, the widest amount) and on "Cash for the week" (today):
    /// on an iPhone SE width the state goes under the name and "Confirm" under the amount, so the
    /// name keeps the room it needs instead of shrinking to "R…".
    @Test
    func rowsWaitingToBeConfirmed() async {
        let store = InMemoryStore(sample: .standard)
        let today = SampleData.defaultReferenceDate
        let rules = SampleData.standard.recurringRules
        for (ruleID, daysAgo) in [(SampleData.IDs.rentRule, 3), (SampleData.IDs.cashRule, 0)] {
            guard let rule = rules.first(where: { $0.id == ruleID }) else { continue }
            await store.save(Transaction(
                // Whole days back from the reference instant, so "3 days" holds in any time zone.
                date: today.addingTimeInterval(-Double(daysAgo) * 86400),
                status: .planned,
                description: rule.name,
                kind: rule.kind,
                categoryID: rule.categoryID,
                amount: rule.amount,
                currency: rule.currency,
                accountID: rule.accountID,
                cardID: rule.cardID,
                destinationAccountID: rule.destinationAccountID,
                exchangeRate: SampleData.standard.settings.currencies.exchangeRate,
                recurringID: rule.id,
            ))
        }
        let viewModel = RecurringPreview.listViewModel(store: store)
        await viewModel.load()
        assertScreenSnapshot(
            of: RecurringView(viewModel: viewModel, onBack: {}, onAdd: {}, onAddSubscription: {}, onOpen: { _ in }),
            width: 320,
            height: 900,
        )
    }

    @Test
    func emptyList() async {
        let store = InMemoryStore(sample: .standard)
        for rule in SampleData.standard.recurringRules {
            try? await store.deleteRecurringRule(id: rule.id)
        }
        let viewModel = RecurringPreview.listViewModel(store: store)
        await viewModel.load()
        assertScreenSnapshot(of: RecurringView(viewModel: viewModel, onBack: {}, onAdd: {}, onAddSubscription: {}, onOpen: { _ in }))
    }

    @Test
    func editingARule() async {
        let viewModel = RecurringPreview.editorViewModel(ruleID: SampleData.IDs.streamingRule)
        await viewModel.load()
        assertScreenSnapshot(
            of: RecurringRuleEditorView(viewModel: viewModel, onBack: {}, onDone: {}, onOpenTransaction: { _ in }),
            height: 1450,
        )
    }

    @Test
    func newRule() async {
        let viewModel = RecurringPreview.editorViewModel(ruleID: nil)
        await viewModel.load()
        assertScreenSnapshot(
            of: RecurringRuleEditorView(viewModel: viewModel, onBack: {}, onDone: {}, onOpenTransaction: { _ in }),
            height: 1200,
        )
    }

    @Test
    func newSubscription() async {
        let viewModel = RecurringPreview.editorViewModel(ruleID: nil, isNewSubscription: true)
        await viewModel.load()
        viewModel.name = "Music"
        viewModel.amountText = "9.99"
        viewModel.subscriptionPeriod = .quarterly
        assertScreenSnapshot(
            of: RecurringRuleEditorView(viewModel: viewModel, onBack: {}, onDone: {}, onOpenTransaction: { _ in }),
        )
    }
}
