import Domain
import DomainSamples
import Foundation
import RecurringDomain
import SwiftUI

/// Screens wired to the sample data in memory, for `#Preview` and snapshot tests.
@MainActor
public enum RecurringPreview {
    public struct UseCases {
        public let overview: any GetRecurringOverviewUseCase
        public let save: any SaveRecurringRuleUseCase
        public let setPaused: any SetRecurringRulePausedUseCase
        public let delete: any DeleteRecurringRuleUseCase
    }

    public static func useCases(store: InMemoryStore, now: Date = SampleData.defaultReferenceDate) -> UseCases {
        let materialize = DefaultMaterializeRecurringUseCase(
            rules: store,
            transactions: store,
            settings: store,
            accounts: store,
            cards: store,
            categories: store,
            categorizationRules: store,
            now: { now },
        )
        return UseCases(
            overview: DefaultGetRecurringOverviewUseCase(
                rules: store, accounts: store, cards: store, categories: store, transactions: store, settings: store,
            ),
            save: DefaultSaveRecurringRuleUseCase(
                rules: store, accounts: store, cards: store, categories: store, settings: store, materialize: materialize, now: { now },
            ),
            setPaused: DefaultSetRecurringRulePausedUseCase(rules: store, materialize: materialize, now: { now }),
            delete: DefaultDeleteRecurringRuleUseCase(rules: store, transactions: store),
        )
    }

    public static func listViewModel(store: InMemoryStore = InMemoryStore(sample: .standard)) -> RecurringViewModel {
        RecurringViewModel(getOverview: useCases(store: store).overview, now: { SampleData.defaultReferenceDate })
    }

    public static func editorViewModel(
        ruleID: UUID?,
        isNewSubscription: Bool = false,
        store: InMemoryStore = InMemoryStore(sample: .standard),
        makeID: () -> UUID = UUID.init,
    ) -> RecurringRuleEditorViewModel {
        let cases = useCases(store: store)
        return RecurringRuleEditorViewModel(
            ruleID: ruleID,
            isNewSubscription: isNewSubscription,
            getOverview: cases.overview,
            save: cases.save,
            setPaused: cases.setPaused,
            delete: cases.delete,
            now: { SampleData.defaultReferenceDate },
            makeID: makeID,
        )
    }

    static func list() -> some View {
        RecurringView(viewModel: listViewModel(), onBack: {}, onAdd: {}, onAddSubscription: {}, onOpen: { _ in })
    }

    static func editor() -> some View {
        RecurringRuleEditorView(
            viewModel: editorViewModel(ruleID: SampleData.IDs.streamingRule),
            onBack: {},
            onDone: {},
            onOpenTransaction: { _ in },
        )
    }
}
