import AccountsPresentation
import AddCardPresentation
import CloudAccountPresentation
import Core
import CreateTransactionPresentation
import CreditCardPresentation
import DebtsPresentation
import DesignSystem
import Domain
import GoalsPresentation
import HomePresentation
import LockPresentation
import OnboardingPresentation
import RecurringPresentation
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
    let onRestoreFile: () -> Void
    let onFinish: (OnboardingFlowView.Exit) -> Void
    @State private var passcodeSetup: PresentedFlow<PasscodeSetupViewModel>?
    /// "Restore from your Keepwell account": the sign-in sheet, and what to do once signed in.
    @State private var restoreAfterSignIn: (() -> Void)?

    var body: some View {
        OnboardingFlowView(
            viewModel: viewModel,
            onImportCSV: onImportCSV,
            onRestoreFile: onRestoreFile,
            onSignInToRestore: container.cloudAccount == nil ? nil : { restore in restoreAfterSignIn = restore },
            onSetUpPasscode: { passcodeSetup = PresentedFlow(viewModel: container.makePasscodeSetupViewModel()) },
            onFinish: onFinish,
        )
        .sheet(isPresented: Binding(get: { restoreAfterSignIn != nil }, set: {
            if !$0 {
                restoreAfterSignIn = nil
            }
        })) {
            if let account = container.cloudAccount {
                ScrollView {
                    CloudAccountSection(viewModel: account).padding()
                }
                .presentationDetents([.medium])
                .onChange(of: account.state) { _, state in
                    // Signed in: sync starts on its own, and onboarding waits for the data to arrive.
                    if case .signedIn = state, let restore = restoreAfterSignIn {
                        restoreAfterSignIn = nil
                        restore()
                    }
                }
            }
        }
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
    @State private var cloudAccount: CloudAccountViewModel?
    @State private var passcodeSetup: PresentedFlow<PasscodeSetupViewModel>?
    private let container: AppContainer
    let onBack: () -> Void
    let onErased: () -> Void
    let onOpenCategories: (TransactionKind) -> Void
    let onOpenPaymentMethods: () -> Void
    let onOpenRecurring: () -> Void
    let onOpenRules: () -> Void

    init(
        container: AppContainer,
        onBack: @escaping () -> Void,
        onErased: @escaping () -> Void,
        onOpenCategories: @escaping (TransactionKind) -> Void,
        onOpenPaymentMethods: @escaping () -> Void,
        onOpenRecurring: @escaping () -> Void,
        onOpenRules: @escaping () -> Void,
    ) {
        _viewModel = State(initialValue: container.makeSettingsViewModel())
        _cloudAccount = State(initialValue: container.cloudAccount)
        self.container = container
        self.onBack = onBack
        self.onErased = onErased
        self.onOpenCategories = onOpenCategories
        self.onOpenPaymentMethods = onOpenPaymentMethods
        self.onOpenRecurring = onOpenRecurring
        self.onOpenRules = onOpenRules
    }

    var body: some View {
        SettingsView(
            viewModel: viewModel,
            onBack: onBack,
            onErased: onErased,
            onSetUpPasscode: { passcodeSetup = PresentedFlow(viewModel: container.makePasscodeSetupViewModel()) },
            onOpenCategories: onOpenCategories,
            onOpenPaymentMethods: onOpenPaymentMethods,
            onOpenRecurring: onOpenRecurring,
            onOpenRules: onOpenRules,
            accountSection: cloudAccount.map { AnyView(CloudAccountSection(viewModel: $0)) },
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

struct RulesRoute: View {
    @State private var viewModel: RulesViewModel
    let onBack: () -> Void

    init(container: AppContainer, onBack: @escaping () -> Void) {
        _viewModel = State(initialValue: container.makeRulesViewModel())
        self.onBack = onBack
    }

    var body: some View {
        RulesView(viewModel: viewModel, onBack: onBack)
            .navigationBarBackButtonHidden()
    }
}

struct PaymentMethodsRoute: View {
    @State private var viewModel: PaymentMethodsViewModel
    let onBack: () -> Void
    let onOpenAccount: (Account) -> Void

    init(container: AppContainer, onBack: @escaping () -> Void, onOpenAccount: @escaping (Account) -> Void) {
        _viewModel = State(initialValue: container.makePaymentMethodsViewModel())
        self.onBack = onBack
        self.onOpenAccount = onOpenAccount
    }

    var body: some View {
        PaymentMethodsView(viewModel: viewModel, onBack: onBack, onOpenAccount: onOpenAccount)
            .navigationBarBackButtonHidden()
    }
}

struct CreditCardRoute: View {
    @State private var viewModel: CreditCardViewModel
    let onBack: () -> Void
    let onPay: () -> Void
    let onSeeAllMovements: () -> Void

    init(
        container: AppContainer,
        accountID: UUID,
        onBack: @escaping () -> Void,
        onPay: @escaping () -> Void,
        onSeeAllMovements: @escaping () -> Void,
    ) {
        _viewModel = State(initialValue: container.makeCreditCardViewModel(accountID: accountID))
        self.onBack = onBack
        self.onPay = onPay
        self.onSeeAllMovements = onSeeAllMovements
    }

    var body: some View {
        CreditCardView(viewModel: viewModel, onBack: onBack, onPay: onPay, onSeeAllMovements: onSeeAllMovements)
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
    let onOpenTransaction: (UUID) -> Void
    let onOpenRecurringRule: (UUID) -> Void
    let onNewMovement: () -> Void

    init(
        container: AppContainer,
        scope: TransactionScope,
        onBack: @escaping () -> Void,
        onOpenTransaction: @escaping (UUID) -> Void,
        onOpenRecurringRule: @escaping (UUID) -> Void,
        onNewMovement: @escaping () -> Void,
    ) {
        let viewModel = container.makeTransactionsViewModel()
        viewModel.scope = scope
        _viewModel = State(initialValue: viewModel)
        self.onBack = onBack
        self.onOpenTransaction = onOpenTransaction
        self.onOpenRecurringRule = onOpenRecurringRule
        self.onNewMovement = onNewMovement
    }

    var body: some View {
        TransactionsView(
            viewModel: viewModel,
            onBack: onBack,
            onOpenTransaction: onOpenTransaction,
            onOpenRecurringRule: onOpenRecurringRule,
            onNewMovement: onNewMovement,
        )
        .navigationBarBackButtonHidden()
        // Back from a movement's detail, where it may have been edited or deleted.
        .onAppear { Task { await viewModel.load() } }
    }
}

/// Recurring movements and subscriptions. The screen reloads itself when it reappears after a rule closes.
struct RecurringRoute: View {
    @State private var viewModel: RecurringViewModel
    let onBack: () -> Void
    let onAdd: () -> Void
    let onOpen: (UUID) -> Void

    init(container: AppContainer, onBack: @escaping () -> Void, onAdd: @escaping () -> Void, onOpen: @escaping (UUID) -> Void) {
        _viewModel = State(initialValue: container.makeRecurringViewModel())
        self.onBack = onBack
        self.onAdd = onAdd
        self.onOpen = onOpen
    }

    var body: some View {
        RecurringView(viewModel: viewModel, onBack: onBack, onAdd: onAdd, onOpen: onOpen)
            .navigationBarBackButtonHidden()
    }
}

/// Savings goals. Its editor and add/withdraw sheets open on top of it, so it reloads by itself.
struct GoalsRoute: View {
    @State private var viewModel: GoalsViewModel
    let onBack: () -> Void

    init(container: AppContainer, onBack: @escaping () -> Void) {
        _viewModel = State(initialValue: container.makeGoalsViewModel())
        self.onBack = onBack
    }

    var body: some View {
        GoalsView(viewModel: viewModel, onBack: onBack)
            .navigationBarBackButtonHidden()
    }
}

/// Loans and personal debts. Their sheets open on top of it, so it reloads by itself.
struct DebtsRoute: View {
    @State private var viewModel: DebtsViewModel
    let onBack: () -> Void

    init(container: AppContainer, onBack: @escaping () -> Void) {
        _viewModel = State(initialValue: container.makeDebtsViewModel())
        self.onBack = onBack
    }

    var body: some View {
        DebtsView(viewModel: viewModel, onBack: onBack)
            .navigationBarBackButtonHidden()
    }
}

extension View {
    /// "Split" on an expense, over whichever tab listed it. It closes itself after splitting.
    func splitBillSheet(_ item: Binding<SplitBillViewModel?>, onDismiss: @escaping () -> Void) -> some View {
        sheet(item: item, onDismiss: onDismiss) { split in
            SplitBillView(viewModel: split, onDone: { item.wrappedValue = nil }, onClose: { item.wrappedValue = nil })
                .presentationDetents([.large])
                .presentationBackground(KWColor.Surface.bg)
        }
    }
}

/// A recurring rule's editor, which closes itself after saving or deleting.
struct RecurringRuleRoute: View {
    @State private var viewModel: RecurringRuleEditorViewModel
    let onBack: () -> Void

    init(container: AppContainer, ruleID: UUID?, onBack: @escaping () -> Void) {
        _viewModel = State(initialValue: container.makeRecurringRuleEditorViewModel(ruleID: ruleID))
        self.onBack = onBack
    }

    var body: some View {
        RecurringRuleEditorView(viewModel: viewModel, onBack: onBack, onDone: onBack)
            .navigationBarBackButtonHidden()
    }
}

/// Wraps a flow's view model so it can drive `fullScreenCover(item:)`.
struct PresentedFlow<ViewModel>: Identifiable {
    let id = UUID()
    let viewModel: ViewModel
}
