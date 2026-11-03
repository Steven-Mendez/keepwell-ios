import AccountsDomain
import DomainSamples
import Foundation

/// Sample-backed view model for `#Preview`s.
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
}
