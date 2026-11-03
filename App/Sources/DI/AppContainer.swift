import AccountsDomain
import AccountsPresentation
import AddCardDomain
import AddCardPresentation
import Core
import Domain
import Foundation
import OnboardingDomain
import OnboardingPresentation
import Persistence
import SwiftData
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

    init(modelContainer: ModelContainer) {
        store = SwiftDataStore(modelContainer: modelContainer)
    }

    #if DEBUG
    func seedSampleData() async {
        let sample = SampleData(referenceDate: .now)
        try? await store.seed(
            settings: sample.settings,
            accounts: sample.accounts,
            cards: sample.cards,
            transactions: sample.transactions,
            categories: sample.categories,
        )
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
}
