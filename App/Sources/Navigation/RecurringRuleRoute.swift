import RecurringPresentation
import SharedPresentation
import SwiftUI

/// Recurring movements and subscriptions. The screen reloads itself when it reappears after a rule
/// closes, and after "Undo" turns a draft it confirmed back into one.
struct RecurringRoute: View {
    @State private var viewModel: RecurringViewModel
    private let container: AppContainer
    private let undo: MovementUndo
    let onBack: () -> Void
    /// `true` for "New subscription", the short form.
    let onAdd: (_ isSubscription: Bool) -> Void
    let onOpen: (UUID) -> Void

    init(container: AppContainer, onBack: @escaping () -> Void, onAdd: @escaping (Bool) -> Void, onOpen: @escaping (UUID) -> Void) {
        _viewModel = State(initialValue: container.makeRecurringViewModel())
        self.container = container
        undo = container.movementUndo
        self.onBack = onBack
        self.onAdd = onAdd
        self.onOpen = onOpen
    }

    var body: some View {
        RecurringView(viewModel: viewModel, onBack: onBack, onAdd: { onAdd(false) }, onAddSubscription: { onAdd(true) }, onOpen: onOpen)
            .navigationBarBackButtonHidden()
            .onChange(of: undo.undoneCount) { Task { await viewModel.load() } }
            // A rule edited on the web or by an assistant, or a payment that arrived by sync.
            .reloadsOnStoreChange(refreshingWith: container) { await viewModel.load() }
    }
}

/// A recurring rule's detail. It reloads when it reappears after its editor or a movement closes,
/// when "Undo" turns a draft it confirmed back into one, and when the store changes (a payment
/// that arrived by sync, the rule edited on the web or by an assistant).
struct RecurringRuleDetailRoute: View {
    @State private var viewModel: RecurringRuleDetailViewModel
    private let container: AppContainer
    let onBack: () -> Void
    let onEdit: () -> Void
    let onOpenTransaction: (UUID) -> Void

    init(
        container: AppContainer,
        ruleID: UUID,
        onBack: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onOpenTransaction: @escaping (UUID) -> Void,
    ) {
        _viewModel = State(initialValue: container.makeRecurringRuleDetailViewModel(ruleID: ruleID))
        self.container = container
        self.onBack = onBack
        self.onEdit = onEdit
        self.onOpenTransaction = onOpenTransaction
    }

    var body: some View {
        RecurringRuleDetailView(viewModel: viewModel, onBack: onBack, onEdit: onEdit, onOpenTransaction: onOpenTransaction)
            .navigationBarBackButtonHidden()
            .onChange(of: container.movementUndo.undoneCount) { Task { await viewModel.load() } }
            .reloadsOnStoreChange(refreshingWith: container) { await viewModel.load() }
    }
}

/// A recurring rule's editor, which closes itself after saving or deleting. `isNewSubscription`
/// opens it on the short subscription form.
struct RecurringRuleRoute: View {
    @State private var viewModel: RecurringRuleEditorViewModel
    let onBack: () -> Void

    init(
        container: AppContainer,
        ruleID: UUID?,
        isNewSubscription: Bool = false,
        onBack: @escaping () -> Void,
    ) {
        _viewModel = State(initialValue: container.makeRecurringRuleEditorViewModel(ruleID: ruleID, isNewSubscription: isNewSubscription))
        self.onBack = onBack
    }

    var body: some View {
        RecurringRuleEditorView(
            viewModel: viewModel,
            onBack: onBack,
            onDone: onBack,
        )
        .navigationBarBackButtonHidden()
    }
}
