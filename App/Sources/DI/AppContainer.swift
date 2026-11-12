import AccountsDomain
import AccountsPresentation
import AddCardDomain
import AddCardPresentation
import CloudAccountData
import CloudAccountPresentation
import Core
import CreateTransactionDomain
import CreateTransactionPresentation
import CreditCardDomain
import CreditCardPresentation
import Domain
import Foundation
import HomeDomain
import HomePresentation
import LockDomain
import LockPresentation
import OnboardingDomain
import OnboardingPresentation
import OSLog
import Persistence
import RecurringDomain
import RecurringPresentation
import SettingsDomain
import SettingsPresentation
import SummaryDomain
import SummaryPresentation
import SwiftData
import TransactionsDomain
import TransactionsPresentation
import UserNotifications
import WidgetKit
#if DEBUG
import DomainSamples
#endif

/// Composition root: the only place that names concrete types and wires Data → Domain → Presentation.
/// Features see protocols only, so swapping storage (e.g. for UI tests) is a change here alone.
@MainActor
final class AppContainer {
    let currencyFormatter = CurrencyFormatter()
    let store: SwiftDataStore
    let preferences = StorePreferences()
    /// The app passcode's hash, in this device's Keychain only.
    let passcodes: any PasscodeRepository = KeychainPasscodeStore()
    /// The Keepwell account and its sync, one per app; `nil` in builds without an API.
    private(set) lazy var cloudAccount: CloudAccountViewModel? = makeCloudAccountViewModel()
    /// One API client per app, shared by the account and its sync.
    private(set) lazy var apiClient: APIClient? = makeAPIClient()
    /// The sync engine behind `cloudAccount`, kept so erasing this iPhone can forget its cursor.
    private(set) lazy var syncEngine: SyncEngine? = makeSyncEngine()

    init(modelContainer: ModelContainer) {
        store = SwiftDataStore(modelContainer: modelContainer)
    }

    #if DEBUG
    func seedSampleData() async {
        // In the app's own language, so Spanish screenshots don't show English movements.
        let language = SampleLanguage(languageCode: Bundle.main.preferredLocalizations.first)
        let sample = SampleData(referenceDate: .now, language: language)
        do {
            try await store.seed(
                settings: sample.settings,
                accounts: sample.accounts,
                cards: sample.cards,
                transactions: sample.transactions,
                categories: sample.categories,
                recurringRules: sample.recurringRules,
                savingsGoals: sample.savingsGoals,
                loans: sample.loans,
                personalDebts: sample.personalDebts,
                categorizationRules: sample.categorizationRules,
            )
        } catch {
            Logger.app.error("Sample data could not be seeded: \(String(describing: error), privacy: .public)")
        }
    }
    #endif

    // MARK: - Onboarding

    func makeGetSettings() -> any GetSettingsUseCase {
        DefaultGetSettingsUseCase(repository: store)
    }

    func makeOnboardingViewModel() -> OnboardingViewModel {
        OnboardingViewModel(
            completeOnboarding: DefaultCompleteOnboardingUseCase(
                settings: store, accounts: store, cards: store, profile: preferences, passcodes: passcodes,
            ),
            restoreFromAccount: makeRestoreFromAccount(),
            notifications: UserNotificationAuthorizer(),
        )
    }

    // MARK: - Accounts

    func makeAccountsViewModel() -> AccountsViewModel {
        AccountsViewModel(
            getOverview: DefaultGetAccountsOverviewUseCase(accounts: store, cards: store, transactions: store, settings: store),
            getPreferredName: makeGetPreferredName(),
        )
    }

    // MARK: - Add card

    func makeAddCardViewModel() -> AddCardViewModel {
        AddCardViewModel(
            getContext: DefaultGetAddCardContextUseCase(settings: store),
            addCredit: DefaultAddCreditCardUseCase(accounts: store, cards: store, settings: store),
            addAccount: DefaultAddAccountUseCase(accounts: store, cards: store),
            getPreferredName: makeGetPreferredName(),
        )
    }

    // MARK: - Home, transactions and summary

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(
            getOverview: DefaultGetHomeOverviewUseCase(
                accounts: store, cards: store, transactions: store, categories: store, settings: store,
                recurringRules: store, savingsGoals: store, loans: store, personalDebts: store,
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store),
            getPreferredName: makeGetPreferredName(),
            discard: DefaultDeleteTransactionUseCase(transactions: store),
            resumeRule: DefaultSetRecurringRulePausedUseCase(rules: store, materialize: makeMaterializeRecurring()),
            deleteRule: DefaultDeleteRecurringRuleUseCase(rules: store, transactions: store),
        )
    }

    /// The one name store behind the lock, home and the cards.
    func makeGetPreferredName() -> any GetPreferredNameUseCase {
        DefaultGetPreferredNameUseCase(profile: preferences)
    }

    func makeTransactionsViewModel() -> TransactionsViewModel {
        TransactionsViewModel(
            getList: DefaultGetTransactionListUseCase(
                transactions: store,
                accounts: store,
                cards: store,
                categories: store,
                settings: store,
                recurringRules: store,
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store),
            deleteTransaction: DefaultDeleteTransactionUseCase(transactions: store),
        )
    }

    func makeSummaryViewModel() -> SummaryViewModel {
        let report = DefaultGetSummaryReportUseCase(transactions: store, categories: store, settings: store, accounts: store)
        let range = DefaultGetRangeSummaryUseCase(transactions: store, settings: store)
        return SummaryViewModel(getReport: report, getRange: range)
    }

    // MARK: - Settings and lock

    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(
            getOverview: DefaultGetSettingsOverviewUseCase(
                settings: store, categories: store, cards: store, accounts: store, transactions: store, rules: store,
                passcodes: passcodes, profile: preferences,
            ),
            updateSettings: DefaultUpdateSettingsUseCase(settings: store),
            changeCurrencies: DefaultChangeCurrenciesUseCase(settings: store, accounts: store, transactions: store),
            exportTransactions: DefaultExportTransactionsUseCase(transactions: store, accounts: store, cards: store, categories: store),
            eraseAllData: DefaultEraseAllDataUseCase(eraser: store),
            removePasscode: DefaultRemovePasscodeUseCase(passcodes: passcodes),
            setPreferredName: DefaultSetPreferredNameUseCase(profile: preferences),
            signOutBeforeErasing: { [weak self] in await self?.cloudAccount?.signOutBeforeErasing() ?? true },
        )
    }

    func makeLockViewModel(prefersPasscode: Bool) -> LockViewModel {
        LockViewModel(
            prefersPasscode: prefersPasscode,
            getContext: DefaultGetLockContextUseCase(passcodes: passcodes, profile: preferences),
            enterPasscode: DefaultEnterPasscodeUseCase(passcodes: passcodes),
            unlockWithDevice: DefaultUnlockWithDeviceUseCase(authenticator: authenticator, passcodes: passcodes),
            recoverPasscode: DefaultRecoverPasscodeUseCase(authenticator: authenticator, passcodes: passcodes),
        )
    }

    func makePasscodeSetupViewModel() -> PasscodeSetupViewModel {
        PasscodeSetupViewModel(setPasscode: DefaultSetPasscodeUseCase(passcodes: passcodes))
    }

    func makePaymentMethodsViewModel() -> PaymentMethodsViewModel {
        PaymentMethodsViewModel(getMethods: DefaultGetPaymentMethodsUseCase(accounts: store, cards: store))
    }

    func makeCategoriesViewModel(kind: TransactionKind) -> CategoriesViewModel {
        CategoriesViewModel(
            kind: kind,
            getCategories: DefaultGetCategoriesUseCase(categories: store),
            save: DefaultSaveCategoryUseCase(categories: store),
            delete: DefaultDeleteCategoryUseCase(categories: store, transactions: store),
            reorder: DefaultReorderCategoriesUseCase(categories: store),
            restoreDefaults: DefaultRestoreDefaultCategoriesUseCase(categories: store),
            getPrincipalCurrency: DefaultGetPrincipalCurrencyUseCase(settings: store),
        )
    }

    let authenticator: any DeviceAuthenticator = LocalDeviceAuthenticator()
    let reminders = ReminderScheduler()
    let widgetSnapshots = WidgetSnapshotStore()

    /// Hands home's latest state to what lives outside the app: widgets and reminders.
    func publish(from home: HomeViewModel) async {
        publishWidgets(from: home)
        var upcoming = home.reminders()
        #if DEBUG
        if AppEnvironment.current.remindsSoon {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            upcoming = upcoming.enumerated().map { index, reminder in reminder.at(.now.addingTimeInterval(Double(5 + index * 4))) }
        }
        #endif
        await reminders.schedule(upcoming)
    }

    func publishWidgets(from home: HomeViewModel) {
        guard let snapshot = home.widgetSnapshot else { return }
        widgetSnapshots.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// After "Delete all my data": nothing of the old data may linger on the home screen.
    func clearOutside() async {
        // The passcode and name live outside the store, so erasing the store alone would keep them.
        await passcodes.removePasscode()
        // With its data gone, this iPhone starts over with the account: the next sync is a first
        // sync again, so the account's data comes back instead of only what's new from now on.
        await syncEngine?.reset()
        await preferences.setPreferredName(nil)
        widgetSnapshots.clear()
        WidgetCenter.shared.reloadAllTimelines()
        await reminders.removeAll()
    }

    // MARK: - Recurring

    /// Records the recurring movements whose day has come. Runs at launch, on returning to the
    /// app and after a rule is saved; it skips what another device already recorded.
    func makeMaterializeRecurring() -> any MaterializeRecurringUseCase {
        DefaultMaterializeRecurringUseCase(
            rules: store,
            transactions: store,
            settings: store,
            accounts: store,
            cards: store,
            categories: store,
        )
    }

    func materializeRecurring() async {
        do {
            try await makeMaterializeRecurring().execute()
        } catch {
            Logger.app.error("Recurring movements could not be recorded: \(String(describing: error), privacy: .public)")
        }
    }

    func makeGetRecurringOverview() -> any GetRecurringOverviewUseCase {
        DefaultGetRecurringOverviewUseCase(
            rules: store, accounts: store, cards: store, categories: store, transactions: store, settings: store,
        )
    }

    func makeRecurringViewModel() -> RecurringViewModel {
        RecurringViewModel(getOverview: makeGetRecurringOverview())
    }

    func makeRecurringRuleEditorViewModel(ruleID: UUID?) -> RecurringRuleEditorViewModel {
        RecurringRuleEditorViewModel(
            ruleID: ruleID,
            getOverview: makeGetRecurringOverview(),
            save: DefaultSaveRecurringRuleUseCase(
                rules: store, accounts: store, cards: store, categories: store, settings: store,
                materialize: makeMaterializeRecurring(),
            ),
            setPaused: DefaultSetRecurringRulePausedUseCase(rules: store, materialize: makeMaterializeRecurring()),
            delete: DefaultDeleteRecurringRuleUseCase(rules: store, transactions: store),
        )
    }

    // MARK: - Create transaction

    func makeCreateTransactionViewModel(type: MovementType = .expense) -> CreateTransactionViewModel {
        let context = makeGetTransactionContext()
        return CreateTransactionViewModel(
            getContext: context,
            save: DefaultSaveTransactionUseCase(
                context: context, transactions: store, recurringRules: store, materialize: makeMaterializeRecurring(),
            ),
            saveCategory: DefaultSaveCategoryUseCase(categories: store),
            receiptSaver: PhotoLibraryReceiptSaver(),
            type: type,
        )
    }

    func makeNewMovementMenuViewModel() -> NewMovementMenuViewModel {
        NewMovementMenuViewModel(getContext: makeGetTransactionContext())
    }

    private func makeGetTransactionContext() -> DefaultGetTransactionContextUseCase {
        DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: store, rules: store,
        )
    }
}

extension AppContainer {
    /// Gives every bank account exactly one card before any screen reads them: older versions
    /// allowed several, and a sync can bring an account whose card hasn't arrived yet.
    func normalizeBankCards() async {
        do {
            try await DefaultNormalizeBankCardsUseCase(accounts: store, cards: store, transactions: store, recurringRules: store).execute()
        } catch {
            Logger.app.error("Bank cards could not be normalized: \(String(describing: error), privacy: .public)")
        }
    }
}
