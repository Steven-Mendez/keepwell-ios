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
    private let onRestoreFile: () -> Void
    private let onSetUpPasscode: () -> Void
    private let onFinish: (Exit) -> Void

    /// `onSetUpPasscode` shows the lock feature's own passcode setup; once it saves, the app calls
    /// `passcodeCreated()` on the view model.
    public init(
        viewModel: OnboardingViewModel,
        onImportCSV: @escaping () -> Void,
        onRestoreFile: @escaping () -> Void = {},
        onSetUpPasscode: @escaping () -> Void,
        onFinish: @escaping (Exit) -> Void,
    ) {
        self.viewModel = viewModel
        self.onImportCSV = onImportCSV
        self.onRestoreFile = onRestoreFile
        self.onSetUpPasscode = onSetUpPasscode
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
            } onRestoreFile: {
                onRestoreFile()
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
        case .name:
            NameView(viewModel: viewModel, onBack: back)
        case .currencies:
            CurrenciesView(viewModel: viewModel, onBack: back)
        case .accounts:
            AccountsView(viewModel: viewModel, onBack: back, onImportCSV: onImportCSV)
        case .protect:
            ProtectView(viewModel: viewModel, onBack: back, onSetUpPasscode: onSetUpPasscode)
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
