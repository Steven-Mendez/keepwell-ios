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
    private let onSignInToRestore: ((@escaping () -> Void) -> Void)?
    private let onSetUpPasscode: () -> Void
    private let onFinish: (Exit) -> Void

    /// `onSetUpPasscode` shows the lock feature's own passcode setup; once it saves, the app calls
    /// `passcodeCreated()` on the view model. `onSignInToRestore` shows the account sign-in and calls
    /// its argument once signed in; `nil` in builds without the Keepwell API.
    public init(
        viewModel: OnboardingViewModel,
        onImportCSV: @escaping () -> Void,
        onRestoreFile: @escaping () -> Void = {},
        onSignInToRestore: ((@escaping () -> Void) -> Void)? = nil,
        onSetUpPasscode: @escaping () -> Void,
        onFinish: @escaping (Exit) -> Void,
    ) {
        self.viewModel = viewModel
        self.onImportCSV = onImportCSV
        self.onRestoreFile = onRestoreFile
        self.onSignInToRestore = onSignInToRestore
        self.onSetUpPasscode = onSetUpPasscode
        self.onFinish = onFinish
    }

    public var body: some View {
        NavigationStack(path: $viewModel.path) {
            WelcomeView(onStart: viewModel.begin)
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
        case .returning:
            ReturningView(
                restoreState: viewModel.restoreState,
                onBack: back,
                onRestoreFromAccount: onSignInToRestore.map { signIn in
                    {
                        signIn {
                            Task {
                                if await viewModel.restore() != nil {
                                    onFinish(.home)
                                }
                            }
                        }
                    }
                },
                onRestoreFromFile: onRestoreFile,
                onStartFresh: viewModel.start,
            )
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
