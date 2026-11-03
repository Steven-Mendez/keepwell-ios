import AccountsPresentation
import AddCardPresentation
import Core
import CreateTransactionPresentation
import CreditCardPresentation
import DesignSystem
import Domain
import HomePresentation
import LockPresentation
import OnboardingPresentation
import SettingsDomain
import SettingsPresentation
import SummaryPresentation
import SwiftUI
import TransactionsPresentation
import UniformTypeIdentifiers

/// When the app asks to unlock again, from the person's settings.
struct LockState {
    var settings: Settings?
    var isLocked = false
    var backgroundedAt: Date?

    private var isEnabled: Bool {
        guard let settings, settings.unlockMethod != .disabled else { return false }
        // Sample data and UI tests drive the app unattended, with no one to authenticate.
        let environment = AppEnvironment.current
        #if DEBUG
        if environment.forcesLock {
            return true
        }
        #endif
        return !environment.isUITesting && !environment.usesSampleData
    }

    var appliesOnLaunch: Bool {
        isEnabled
    }

    var hidesAmounts: Bool {
        settings?.hidesAmountsInAppSwitcher == true
    }

    func shouldRelock(now: Date) -> Bool {
        guard isEnabled, let backgroundedAt, let settings else { return false }
        return now.timeIntervalSince(backgroundedAt) >= settings.relockAfter
    }
}

/// The tab screens' view models, created once when the main app appears so switching tabs keeps
/// each screen's scroll, filter and search.
@MainActor
final class MainScreens {
    let home: HomeViewModel
    let transactions: TransactionsViewModel
    let accounts: AccountsViewModel
    let summary: SummaryViewModel

    init(container: AppContainer) {
        home = container.makeHomeViewModel()
        transactions = container.makeTransactionsViewModel()
        accounts = container.makeAccountsViewModel()
        summary = container.makeSummaryViewModel()
    }

    func reload() async {
        async let home: Void = home.load()
        async let transactions: Void = transactions.load()
        async let accounts: Void = accounts.load()
        async let summary: Void = summary.load()
        _ = await (home, transactions, accounts, summary)
    }
}

// MARK: - Route screens

// Each pushed screen keeps its view model in `@State`, so re-rendering the stack doesn't
// recreate it and lose what the person was doing.

struct SettingsRoute: View {
    @State private var viewModel: SettingsViewModel
    @State private var passcodeSetup: PresentedFlow<PasscodeSetupViewModel>?
    private let container: AppContainer
    let onBack: () -> Void
    let onErased: () -> Void

    init(container: AppContainer, onBack: @escaping () -> Void, onErased: @escaping () -> Void) {
        _viewModel = State(initialValue: container.makeSettingsViewModel())
        self.container = container
        self.onBack = onBack
        self.onErased = onErased
    }

    var body: some View {
        SettingsView(
            viewModel: viewModel,
            onBack: onBack,
            onErased: onErased,
            onSetUpPasscode: { passcodeSetup = PresentedFlow(viewModel: container.makePasscodeSetupViewModel()) },
        )
        .navigationBarBackButtonHidden()
        .fullScreenCover(item: $passcodeSetup, onDismiss: reload) { flow in
            PasscodeSetupView(viewModel: flow.viewModel, isChanging: viewModel.overview?.hasPasscode == true) {
                passcodeSetup = nil
            }
        }
    }

    private func reload() {
        Task { await viewModel.load() }
    }
}

struct CreditCardRoute: View {
    @State private var viewModel: CreditCardViewModel
    let addsAdditional: Bool
    let onBack: () -> Void
    let onPay: () -> Void
    let onOpenAdditional: (UUID) -> Void

    init(
        container: AppContainer,
        accountID: UUID,
        addsAdditional: Bool,
        onBack: @escaping () -> Void,
        onPay: @escaping () -> Void,
        onOpenAdditional: @escaping (UUID) -> Void,
    ) {
        _viewModel = State(initialValue: container.makeCreditCardViewModel(accountID: accountID))
        self.addsAdditional = addsAdditional
        self.onBack = onBack
        self.onPay = onPay
        self.onOpenAdditional = onOpenAdditional
    }

    var body: some View {
        CreditCardView(
            viewModel: viewModel,
            startsAddingAdditional: addsAdditional,
            onBack: onBack,
            onPay: onPay,
            onOpenAdditional: onOpenAdditional,
        )
        .navigationBarBackButtonHidden()
    }
}

struct AdditionalCardRoute: View {
    @State private var viewModel: CreditCardViewModel
    let cardID: UUID
    let onBack: () -> Void

    init(container: AppContainer, accountID: UUID, cardID: UUID, onBack: @escaping () -> Void) {
        _viewModel = State(initialValue: container.makeCreditCardViewModel(accountID: accountID))
        self.cardID = cardID
        self.onBack = onBack
    }

    var body: some View {
        AdditionalCardView(viewModel: viewModel, cardID: cardID, onBack: onBack)
            .navigationBarBackButtonHidden()
    }
}

/// Wraps a flow's view model so it can drive `fullScreenCover(item:)`.
struct PresentedFlow<ViewModel>: Identifiable {
    let id = UUID()
    let viewModel: ViewModel
}
