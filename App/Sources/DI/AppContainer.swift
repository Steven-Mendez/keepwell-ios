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
    /// Started with the container so it hears CloudKit uploads from launch on.
    let backupStatus = BackupStatusTracker()

    init(modelContainer: ModelContainer) {
        store = SwiftDataStore(modelContainer: modelContainer)
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
            completeOnboarding: DefaultCompleteOnboardingUseCase(settings: store, accounts: store, cards: store, backup: preferences),
            restoreFromBackup: DefaultRestoreFromBackupUseCase(settings: store, backup: preferences),
            notifications: UserNotificationAuthorizer(),
        )
    }

    // MARK: - Accounts

    func makeAccountsViewModel() -> AccountsViewModel {
        AccountsViewModel(
            getOverview: DefaultGetAccountsOverviewUseCase(accounts: store, cards: store, transactions: store, settings: store),
            reconcileCash: DefaultReconcileCashUseCase(transactions: store, settings: store),
            withdrawCash: DefaultWithdrawCashUseCase(transactions: store, cards: store, settings: store),
        )
    }

    // MARK: - Add card

    func makeAddCardViewModel() -> AddCardViewModel {
        AddCardViewModel(
            getContext: DefaultGetAddCardContextUseCase(settings: store, accounts: store),
            addCredit: DefaultAddCreditCardUseCase(accounts: store, cards: store, settings: store),
            addDebit: DefaultAddDebitCardUseCase(accounts: store, cards: store),
            addAccount: DefaultAddAccountUseCase(accounts: store, cards: store),
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
        )
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
            ),
            updateSettings: DefaultUpdateSettingsUseCase(settings: store),
            setICloudBackup: DefaultSetICloudBackupUseCase(backup: preferences, settings: store),
            exportTransactions: DefaultExportTransactionsUseCase(transactions: store, accounts: store, cards: store, categories: store),
            importTransactions: makeImportTransactions(),
            createBackup: DefaultCreateBackupUseCase(
                settings: store,
                accounts: store,
                cards: store,
                categories: store,
                transactions: store,
            ),
            restoreBackup: DefaultRestoreBackupUseCase(
                eraser: store, settings: store, accounts: store, cards: store, categories: store, transactions: store,
            ),
            eraseAllData: DefaultEraseAllDataUseCase(eraser: store),
        )
    }

    let authenticator: any DeviceAuthenticator = LocalDeviceAuthenticator()
    let reminders = ReminderScheduler()
    let widgetSnapshots = WidgetSnapshotStore()

    /// Hands home's latest state to what lives outside the app: widgets and reminders.
    func publish(from home: HomeViewModel) async {
        if let snapshot = home.widgetSnapshot {
            widgetSnapshots.save(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        }
        var upcoming = home.reminders()
        #if DEBUG
        if AppEnvironment.current.remindsSoon {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            upcoming = upcoming.enumerated().map { index, reminder in reminder.at(.now.addingTimeInterval(Double(5 + index * 4))) }
        }
        #endif
        await reminders.schedule(upcoming)
    }

    /// After "Delete all my data": nothing of the old data may linger on the home screen.
    func clearOutside() async {
        widgetSnapshots.clear()
        WidgetCenter.shared.reloadAllTimelines()
        await reminders.removeAll()
    }

    func makeImportTransactions() -> any ImportTransactionsUseCase {
        DefaultImportTransactionsUseCase(transactions: store, accounts: store, cards: store, categories: store, settings: store)
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
            addAdditional: DefaultAddAdditionalCardUseCase(cards: store),
            updateAdditional: DefaultUpdateAdditionalCardUseCase(cards: store),
            removeAdditional: DefaultRemoveAdditionalCardUseCase(cards: store),
            setCardFrozen: DefaultSetCardFrozenUseCase(cards: store),
            setCardColor: DefaultSetCardColorUseCase(cards: store),
            renameAccount: DefaultRenameAccountUseCase(accounts: store),
        )
    }

    // MARK: - Debit card

    func makeDebitCardViewModel(cardID: UUID) -> DebitCardViewModel {
        DebitCardViewModel(
            cardID: cardID,
            getDetail: DefaultGetDebitCardDetailUseCase(accounts: store, cards: store, transactions: store, settings: store),
            setFrozen: DefaultSetCardFrozenUseCase(cards: store),
            setColor: DefaultSetCardColorUseCase(cards: store),
            renameAccount: DefaultRenameAccountUseCase(accounts: store),
            removeCard: DefaultRemoveCardUseCase(cards: store),
        )
    }

    // MARK: - Create transaction

    func makeCreateTransactionViewModel(kind: TransactionKind = .expense) -> CreateTransactionViewModel {
        let context = DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: store,
        )
        return CreateTransactionViewModel(
            getContext: context,
            save: DefaultSaveTransactionUseCase(context: context, transactions: store),
            kind: kind,
        )
    }
}
