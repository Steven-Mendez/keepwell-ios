import DesignSystem
import Domain
import SwiftUI

/// Hosts the onboarding steps in their own stack so the back buttons and the edge swipe work.
public struct OnboardingFlowView: View {
    public enum Exit: Sendable {
        case home
        case logFirstExpense
    }

    @Bindable private var viewModel: OnboardingViewModel
    private let onImportCSV: () -> Void
    private let onFinish: (Exit) -> Void

    public init(viewModel: OnboardingViewModel, onImportCSV: @escaping () -> Void, onFinish: @escaping (Exit) -> Void) {
        self.viewModel = viewModel
        self.onImportCSV = onImportCSV
        self.onFinish = onFinish
    }

    public var body: some View {
        NavigationStack(path: $viewModel.path) {
            WelcomeView(restoreState: viewModel.restoreState) {
                viewModel.start()
            } onRestore: {
                Task {
                    if await viewModel.restore() != nil {
                        onFinish(.home)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: OnboardingViewModel.Step.self) { step in
                destination(step)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
    }

    @ViewBuilder
    private func destination(_ step: OnboardingViewModel.Step) -> some View {
        switch step {
        case .currencies:
            CurrenciesView(viewModel: viewModel, onBack: back)
        case .accounts:
            AccountsView(viewModel: viewModel, onBack: back, onImportCSV: onImportCSV)
        case .privacy:
            PrivacyView(viewModel: viewModel, onBack: back)
        case .done:
            DoneView(viewModel: viewModel) {
                onFinish(.logFirstExpense)
            } onGoHome: {
                onFinish(.home)
            }
            .navigationBarBackButtonHidden()
        }
    }

    private func back() {
        _ = viewModel.path.popLast()
    }
}
