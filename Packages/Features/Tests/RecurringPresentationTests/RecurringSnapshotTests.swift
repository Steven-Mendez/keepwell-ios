import DomainSamples
import FeatureTestSupport
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
