import DesignSystem
import SwiftUI

/// Hosts the create-movement steps in their own stack.
public struct CreateTransactionFlowView: View {
    @Bindable private var viewModel: CreateTransactionViewModel
    private let onClose: () -> Void

    public init(viewModel: CreateTransactionViewModel, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack(path: $viewModel.path) {
            destination(viewModel.rootStep)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: CreateTransactionViewModel.Step.self) { step in
                    destination(step).toolbar(.hidden, for: .navigationBar)
                }
        }
        .task {
            if viewModel.context == nil {
                await viewModel.load()
            }
        }
    }

    @ViewBuilder
    private func destination(_ step: CreateTransactionViewModel.Step) -> some View {
        // The first screen closes the flow; every later one goes back a step.
        let leave = step == viewModel.rootStep ? onClose : back
        switch step {
        case .accounts: AccountsStepView(viewModel: viewModel, onBack: leave)
        case .amount: AmountView(viewModel: viewModel, onBack: leave)
        case .category: CategoryView(viewModel: viewModel, onBack: back)
        case .method: MethodView(viewModel: viewModel, onBack: back)
        case .review: ReviewView(viewModel: viewModel, onBack: back)
        case .saved: SavedView(viewModel: viewModel, onClose: onClose).navigationBarBackButtonHidden()
        }
    }

    private func back() {
        _ = viewModel.path.popLast()
    }
}
