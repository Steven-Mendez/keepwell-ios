import DesignSystem
import SwiftUI

/// Hosts the add-card steps in their own stack, presented over the accounts screen.
public struct AddCardFlowView: View {
    @Bindable private var viewModel: AddCardViewModel
    private let onExit: (AddCardViewModel.Exit) -> Void

    public init(viewModel: AddCardViewModel, onExit: @escaping (AddCardViewModel.Exit) -> Void) {
        self.viewModel = viewModel
        self.onExit = onExit
    }

    public var body: some View {
        NavigationStack(path: $viewModel.path) {
            AddCardTypeView(viewModel: viewModel) { onExit(.close) }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: AddCardViewModel.Step.self) { step in
                    destination(step).toolbar(.hidden, for: .navigationBar)
                }
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private func destination(_ step: AddCardViewModel.Step) -> some View {
        switch step {
        case .plastic:
            PlasticView(viewModel: viewModel, onBack: back)
        case .debt:
            DebtView(viewModel: viewModel, onBack: back)
        case .done:
            CardAddedView(viewModel: viewModel) {
                onExit(viewModel.createdAccount.map { .viewCreditCard($0.id) } ?? .close)
            } onAddAdditional: {
                onExit(viewModel.createdAccount.map { .addAdditional($0.id) } ?? .close)
            } onAddAnother: {
                viewModel.restart()
            }
            .navigationBarBackButtonHidden()
        }
    }

    private func back() {
        _ = viewModel.path.popLast()
    }
}
