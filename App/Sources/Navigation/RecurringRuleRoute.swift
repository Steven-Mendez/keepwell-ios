import RecurringPresentation
import SwiftUI

/// A recurring rule's editor, which closes itself after saving or deleting. `isNewSubscription`
/// opens it on the short subscription form.
struct RecurringRuleRoute: View {
    @State private var viewModel: RecurringRuleEditorViewModel
    let onBack: () -> Void
    let onOpenTransaction: (UUID) -> Void
    let onSeeAllRecorded: ((UUID) -> Void)?

    init(
        container: AppContainer,
        ruleID: UUID?,
        isNewSubscription: Bool = false,
        onBack: @escaping () -> Void,
        onOpenTransaction: @escaping (UUID) -> Void,
        onSeeAllRecorded: ((UUID) -> Void)? = nil,
    ) {
        _viewModel = State(initialValue: container.makeRecurringRuleEditorViewModel(ruleID: ruleID, isNewSubscription: isNewSubscription))
        self.onBack = onBack
        self.onOpenTransaction = onOpenTransaction
        self.onSeeAllRecorded = onSeeAllRecorded
    }

    var body: some View {
        RecurringRuleEditorView(
            viewModel: viewModel,
            onBack: onBack,
            onDone: onBack,
            onOpenTransaction: onOpenTransaction,
            onSeeAllRecorded: onSeeAllRecorded,
        )
        .navigationBarBackButtonHidden()
    }
}
