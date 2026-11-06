import AccountsDomain
import AccountsPresentation
import AddCardDomain
import AddCardPresentation
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
    /// Started with the container so it hears CloudKit uploads from launch on.
    let backupStatus = BackupStatusTracker()

    init(modelContainer: ModelContainer) {
        store = SwiftDataStore(modelContainer: modelContainer)
    }

    /// Gives every bank account exactly one card before any screen reads them: older versions
    /// allowed several, and a sync can bring an account whose card hasn't arrived yet.
    func normalizeBankCards() async {
        do {
            try await DefaultNormalizeBankCardsUseCase(accounts: store, cards: store, transactions: store).execute()
        } catch {
            Logger.app.error("Bank cards could not be normalized: \(String(describing: error), privacy: .public)")
        }
    }

    #if DEBUG
    func seedSampleData() async {
        let sample = SampleData(referenceDate: .now)
        do {
            try await store.seed(
                settings: sample.settings,
                accounts: sample.accounts,
                cards: sample.cards,
                transactions: sample.transactions,
                categories: sample.categories,
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
                settings: store, accounts: store, cards: store, backup: preferences, profile: preferences, passcodes: passcodes,
            ),
            restoreFromBackup: DefaultRestoreFromBackupUseCase(settings: store, backup: preferences),
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
                accounts: store,
                cards: store,
                transactions: store,
                categories: store,
                settings: store,
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store),
            getPreferredName: makeGetPreferredName(),
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
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store),
            deleteTransaction: DefaultDeleteTransactionUseCase(transactions: store),
        )
    }

    func makeSummaryViewModel() -> SummaryViewModel {
        SummaryViewModel(getReport: DefaultGetSummaryReportUseCase(transactions: store, categories: store, settings: store))
    }

    // MARK: - Settings and lock

    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(
            getOverview: DefaultGetSettingsOverviewUseCase(
                settings: store, categories: store, cards: store, backup: preferences, status: backupStatus,
                passcodes: passcodes, profile: preferences,
            ),
            updateSettings: DefaultUpdateSettingsUseCase(settings: store),
            setICloudBackup: DefaultSetICloudBackupUseCase(backup: preferences, settings: store),
            exportTransactions: DefaultExportTransactionsUseCase(transactions: store, accounts: store, cards: store, categories: store),
            importTransactions: makeImportTransactions(),
            createBackup: DefaultCreateBackupUseCase(store: store),
            restoreBackup: makeRestoreBackup(),
            eraseAllData: DefaultEraseAllDataUseCase(eraser: store, cloud: makeCloudCopyEraser()),
            removePasscode: DefaultRemovePasscodeUseCase(passcodes: passcodes),
            setPreferredName: DefaultSetPreferredNameUseCase(profile: preferences),
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

    func makeRestoreBackup() -> any RestoreBackupUseCase {
        DefaultRestoreBackupUseCase(store: store)
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
        await preferences.setPreferredName(nil)
        widgetSnapshots.clear()
        WidgetCenter.shared.reloadAllTimelines()
        await reminders.removeAll()
    }

    func makeImportTransactions() -> any ImportTransactionsUseCase {
        DefaultImportTransactionsUseCase(transactions: store, accounts: store, cards: store, categories: store, settings: store)
    }

    /// Sample-data and UI-test runs keep an in-memory store, so erasing them must never reach the
    /// real iCloud copy.
    private func makeCloudCopyEraser() -> (any CloudCopyEraser)? {
        let environment = AppEnvironment.current
        guard !environment.isUITesting, !environment.usesSampleData else { return nil }
        return CloudKitCopyEraser(containerIdentifier: environment.cloudKitContainer)
    }

    // MARK: - Credit card

    func makeCreditCardViewModel(accountID: UUID) -> CreditCardViewModel {
        CreditCardViewModel(
            accountID: accountID,
            getDetail: DefaultGetCreditCardDetailUseCase(
                accounts: store,
                cards: store,
                transactions: store,
                categories: store,
                settings: store,
            ),
            updateTerms: DefaultUpdateCreditTermsUseCase(accounts: store),
            setCardColor: DefaultSetCardColorUseCase(cards: store),
            setCardDetails: DefaultSetCardDetailsUseCase(cards: store),
            renameAccount: DefaultRenameAccountUseCase(accounts: store),
            getPreferredName: makeGetPreferredName(),
        )
    }

    // MARK: - Bank account and its card

    func makeDebitCardViewModel(accountID: UUID) -> DebitCardViewModel {
        DebitCardViewModel(
            accountID: accountID,
            getDetail: DefaultGetDebitCardDetailUseCase(
                accounts: store, cards: store, transactions: store, categories: store, settings: store,
            ),
            setColor: DefaultSetCardColorUseCase(cards: store),
            setDetails: DefaultSetCardDetailsUseCase(cards: store),
            renameAccount: DefaultRenameAccountUseCase(accounts: store),
            deleteAccount: DefaultDeleteAccountUseCase(accounts: store, cards: store, transactions: store),
            getPreferredName: makeGetPreferredName(),
        )
    }

    // MARK: - Create transaction

    func makeCreateTransactionViewModel(type: MovementType = .expense) -> CreateTransactionViewModel {
        let context = makeGetTransactionContext()
        return CreateTransactionViewModel(
            getContext: context,
            save: DefaultSaveTransactionUseCase(context: context, transactions: store),
            saveCategory: DefaultSaveCategoryUseCase(categories: store),
            receiptSaver: PhotoLibraryReceiptSaver(),
            type: type,
        )
    }

    func makeNewMovementMenuViewModel() -> NewMovementMenuViewModel {
        NewMovementMenuViewModel(getContext: makeGetTransactionContext())
    }

    private func makeGetTransactionContext() -> DefaultGetTransactionContextUseCase {
        DefaultGetTransactionContextUseCase(settings: store, categories: store, accounts: store, cards: store, transactions: store)
    }
}
