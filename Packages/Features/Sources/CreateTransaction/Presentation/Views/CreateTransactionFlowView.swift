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
            AmountView(viewModel: viewModel, onClose: onClose)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: CreateTransactionViewModel.Step.self) { step in
                    destination(step).toolbar(.hidden, for: .navigationBar)
                }
        }
    }

    @ViewBuilder
    private func destination(_ step: CreateTransactionViewModel.Step) -> some View {
        switch step {
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
