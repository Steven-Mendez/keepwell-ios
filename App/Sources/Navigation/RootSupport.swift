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

/// Onboarding with the lock feature's passcode setup over it, so the protect step reuses the
/// same screen and rules as Settings.
struct OnboardingRoute: View {
    let container: AppContainer
    let viewModel: OnboardingViewModel
    let onImportCSV: () -> Void
    let onFinish: (OnboardingFlowView.Exit) -> Void
    @State private var passcodeSetup: PresentedFlow<PasscodeSetupViewModel>?

    var body: some View {
        OnboardingFlowView(
            viewModel: viewModel,
            onImportCSV: onImportCSV,
            onSetUpPasscode: { passcodeSetup = PresentedFlow(viewModel: container.makePasscodeSetupViewModel()) },
            onFinish: onFinish,
        )
        .fullScreenCover(item: $passcodeSetup) { flow in
            PasscodeSetupView(viewModel: flow.viewModel, isChanging: viewModel.hasPasscode) {
                if flow.viewModel.isSaved {
                    viewModel.passcodeCreated()
                }
                passcodeSetup = nil
            }
        }
    }
}

struct SettingsRoute: View {
    @State private var viewModel: SettingsViewModel
    @State private var passcodeSetup: PresentedFlow<PasscodeSetupViewModel>?
    private let container: AppContainer
    let onBack: () -> Void
    let onErased: () -> Void
    let onOpenCategories: (TransactionKind) -> Void

    init(
        container: AppContainer,
        onBack: @escaping () -> Void,
        onErased: @escaping () -> Void,
        onOpenCategories: @escaping (TransactionKind) -> Void,
    ) {
        _viewModel = State(initialValue: container.makeSettingsViewModel())
        self.container = container
        self.onBack = onBack
        self.onErased = onErased
        self.onOpenCategories = onOpenCategories
    }

    var body: some View {
        SettingsView(
            viewModel: viewModel,
            onBack: onBack,
            onErased: onErased,
            onSetUpPasscode: { passcodeSetup = PresentedFlow(viewModel: container.makePasscodeSetupViewModel()) },
            onOpenCategories: onOpenCategories,
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

struct CategoriesRoute: View {
    @State private var viewModel: CategoriesViewModel
    let onBack: () -> Void

    init(container: AppContainer, kind: TransactionKind, onBack: @escaping () -> Void) {
        _viewModel = State(initialValue: container.makeCategoriesViewModel(kind: kind))
        self.onBack = onBack
    }

    var body: some View {
        CategoriesView(viewModel: viewModel, onBack: onBack)
            .navigationBarBackButtonHidden()
    }
}

struct CreditCardRoute: View {
    @State private var viewModel: CreditCardViewModel
    let addsAdditional: Bool
    let onBack: () -> Void
    let onPay: () -> Void
    let onOpenAdditional: (UUID) -> Void
    let onSeeAllMovements: () -> Void

    init(
        container: AppContainer,
        accountID: UUID,
        addsAdditional: Bool,
        onBack: @escaping () -> Void,
        onPay: @escaping () -> Void,
        onOpenAdditional: @escaping (UUID) -> Void,
        onSeeAllMovements: @escaping () -> Void,
    ) {
        _viewModel = State(initialValue: container.makeCreditCardViewModel(accountID: accountID))
        self.addsAdditional = addsAdditional
        self.onBack = onBack
        self.onPay = onPay
        self.onOpenAdditional = onOpenAdditional
        self.onSeeAllMovements = onSeeAllMovements
    }

    var body: some View {
        CreditCardView(
            viewModel: viewModel,
            startsAddingAdditional: addsAdditional,
            onBack: onBack,
            onPay: onPay,
            onOpenAdditional: onOpenAdditional,
            onSeeAllMovements: onSeeAllMovements,
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

struct DebitCardRoute: View {
    @State private var viewModel: DebitCardViewModel
    let onBack: () -> Void
    let onSeeAllMovements: (UUID) -> Void

    init(
        container: AppContainer,
        accountID: UUID,
        onBack: @escaping () -> Void,
        onSeeAllMovements: @escaping (UUID) -> Void,
    ) {
        _viewModel = State(initialValue: container.makeDebitCardViewModel(accountID: accountID))
        self.onBack = onBack
        self.onSeeAllMovements = onSeeAllMovements
    }

    var body: some View {
        DebitCardView(viewModel: viewModel, onBack: onBack, onSeeAllMovements: onSeeAllMovements)
            .navigationBarBackButtonHidden()
    }
}

/// The movement list pushed from an account. It has its own view model so filtering it
/// leaves the Transactions tab as the person left it.
struct TransactionsRoute: View {
    @State private var viewModel: TransactionsViewModel
    let onBack: () -> Void
    let onNewMovement: () -> Void

    init(container: AppContainer, scope: TransactionScope, onBack: @escaping () -> Void, onNewMovement: @escaping () -> Void) {
        let viewModel = container.makeTransactionsViewModel()
        viewModel.scope = scope
        _viewModel = State(initialValue: viewModel)
        self.onBack = onBack
        self.onNewMovement = onNewMovement
    }

    var body: some View {
        TransactionsView(viewModel: viewModel, onBack: onBack, onNewMovement: onNewMovement)
            .navigationBarBackButtonHidden()
    }
}

/// Wraps a flow's view model so it can drive `fullScreenCover(item:)`.
struct PresentedFlow<ViewModel>: Identifiable {
    let id = UUID()
    let viewModel: ViewModel
}
