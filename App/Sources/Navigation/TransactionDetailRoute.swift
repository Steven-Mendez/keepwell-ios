import CreateTransactionPresentation
import DebtsPresentation
import DesignSystem
import Domain
import SwiftUI
import TransactionsPresentation

/// A movement's detail. It owns what opens over it (the edit flow, the receipt, "Split") and
/// reloads itself when they close, so it always shows the movement as stored.
struct TransactionDetailRoute: View {
    @State private var viewModel: TransactionDetailViewModel
    @State private var editing: PresentedFlow<CreateTransactionViewModel>?
    @State private var receipt: PresentedFlow<CreateTransactionViewModel>?
    @State private var splitBill: SplitBillViewModel?
    private let container: AppContainer
    let onBack: () -> Void
    let onOpenRecurringRule: (UUID) -> Void
    let onShowTag: (String) -> Void

    init(
        container: AppContainer,
        id: UUID,
        onBack: @escaping () -> Void,
        onOpenRecurringRule: @escaping (UUID) -> Void,
        onShowTag: @escaping (String) -> Void,
    ) {
        _viewModel = State(initialValue: container.makeTransactionDetailViewModel(id: id))
        self.container = container
        self.onBack = onBack
        self.onOpenRecurringRule = onOpenRecurringRule
        self.onShowTag = onShowTag
    }

    var body: some View {
        TransactionDetailView(
            viewModel: viewModel,
            actions: TransactionDetailView.Actions(
                back: onBack,
                edit: { editing = PresentedFlow(viewModel: container.makeEditTransactionViewModel(id: $0.id)) },
                receipt: { receipt = PresentedFlow(viewModel: container.makeTransactionReceiptViewModel(id: $0.id)) },
                split: { splitBill = container.makeSplitBillViewModel($0) },
                openRecurringRule: onOpenRecurringRule,
                showTag: onShowTag,
            ),
        )
        .navigationBarBackButtonHidden()
        .fullScreenCover(item: $editing, onDismiss: reload) { flow in
            CreateTransactionFlowView(viewModel: flow.viewModel) {
                viewModel.notice = flow.viewModel.completionNotice
                editing = nil
            }
        }
        .sheet(item: $receipt) { flow in
            CreateTransactionFlowView(viewModel: flow.viewModel) { receipt = nil }
                .presentationBackground(KWColor.Surface.bg)
        }
        .splitBillSheet($splitBill, onDismiss: reload)
    }

    private func reload() {
        Task { await viewModel.load() }
    }
}
