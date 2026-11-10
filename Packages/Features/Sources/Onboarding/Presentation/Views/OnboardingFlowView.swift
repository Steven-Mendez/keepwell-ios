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
    private let accountStep: AnyView?
    private let onImportCSV: () -> Void
    private let onSetUpPasscode: () -> Void
    private let onFinish: (Exit) -> Void

    /// `accountStep` is the sign-in screen the app builds from the account feature; it calls
    /// `continueWithoutAccount()` or `signedIn(canSync:)` on the view model. `nil` in builds
    /// without the Keepwell API. `onSetUpPasscode` shows the lock feature's own passcode setup;
    /// once it saves, the app calls `passcodeCreated()` on the view model.
    public init(
        viewModel: OnboardingViewModel,
        accountStep: AnyView? = nil,
        onImportCSV: @escaping () -> Void,
        onSetUpPasscode: @escaping () -> Void,
        onFinish: @escaping (Exit) -> Void,
    ) {
        self.viewModel = viewModel
        self.accountStep = accountStep
        self.onImportCSV = onImportCSV
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
        case .account:
            accountStep
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
