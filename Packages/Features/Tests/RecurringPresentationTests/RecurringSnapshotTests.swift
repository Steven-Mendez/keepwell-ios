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
        assertScreenSnapshot(of: RecurringView(viewModel: viewModel, onBack: {}, onAdd: {}, onOpen: { _ in }), height: 900)
    }

    @Test
    func emptyList() async {
        let store = InMemoryStore(sample: .standard)
        for rule in SampleData.standard.recurringRules {
            try? await store.deleteRecurringRule(id: rule.id)
        }
        let viewModel = RecurringPreview.listViewModel(store: store)
        await viewModel.load()
        assertScreenSnapshot(of: RecurringView(viewModel: viewModel, onBack: {}, onAdd: {}, onOpen: { _ in }))
    }

    @Test
    func editingARule() async {
        let viewModel = RecurringPreview.editorViewModel(ruleID: SampleData.IDs.streamingRule)
        await viewModel.load()
        assertScreenSnapshot(of: RecurringRuleEditorView(viewModel: viewModel, onBack: {}, onDone: {}), height: 1450)
    }

    @Test
    func newRule() async {
        let viewModel = RecurringPreview.editorViewModel(ruleID: nil)
        await viewModel.load()
        assertScreenSnapshot(of: RecurringRuleEditorView(viewModel: viewModel, onBack: {}, onDone: {}), height: 1200)
    }
}
