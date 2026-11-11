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
            getPreferredName: DefaultGetPreferredNameUseCase(profile: InMemoryPasscodeStore(name: "Steven")),
        )
    }

    static func debitCardViewModel(accountID: UUID = SampleData.IDs.savings) -> DebitCardViewModel {
        let store = InMemoryStore(sample: .standard)
        return DebitCardViewModel(
            accountID: accountID,
            getDetail: DefaultGetDebitCardDetailUseCase(
                accounts: store, cards: store, transactions: store, categories: store, settings: store,
            ),
            setColor: DefaultSetCardColorUseCase(cards: store),
            setDetails: DefaultSetCardDetailsUseCase(cards: store),
            setNumber: DefaultSetCardNumberUseCase(cards: store),
            renameAccount: DefaultRenameAccountUseCase(accounts: store),
            deleteAccount: DefaultDeleteAccountUseCase(accounts: store, cards: store, transactions: store),
            getPreferredName: DefaultGetPreferredNameUseCase(profile: InMemoryPasscodeStore(name: "Steven")),
        )
    }
}
