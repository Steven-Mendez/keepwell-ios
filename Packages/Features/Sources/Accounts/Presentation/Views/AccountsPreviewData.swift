import AccountsDomain
import Domain
import DomainSamples
import Foundation

/// Sample-backed view models for `#Preview`s.
@MainActor
enum AccountsPreviewData {
    static func viewModel() -> AccountsViewModel {
        let store = InMemoryStore(sample: .standard)
        return AccountsViewModel(
            getOverview: DefaultGetAccountsOverviewUseCase(accounts: store, cards: store, transactions: store, settings: store),
            reconcileCash: DefaultReconcileCashUseCase(transactions: store, settings: store),
            withdrawCash: DefaultWithdrawCashUseCase(transactions: store, cards: store, settings: store),
        )
    }

    static func debitCardViewModel(cardID: UUID = SampleData.IDs.savingsDebit) -> DebitCardViewModel {
        let store = InMemoryStore(sample: .standard)
        return DebitCardViewModel(
            cardID: cardID,
            getDetail: DefaultGetDebitCardDetailUseCase(accounts: store, cards: store, transactions: store, settings: store),
            setFrozen: DefaultSetCardFrozenUseCase(cards: store),
            setColor: DefaultSetCardColorUseCase(cards: store),
            renameAccount: DefaultRenameAccountUseCase(accounts: store),
            removeCard: DefaultRemoveCardUseCase(cards: store),
        )
    }
}
