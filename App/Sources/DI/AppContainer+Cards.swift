import AccountsDomain
import AccountsPresentation
import CreditCardDomain
import CreditCardPresentation
import Domain
import Foundation

/// The screens of one account: credit card, bank account with its debit card, and cash.
extension AppContainer {
    // MARK: - Credit card

    func makeCreditCardViewModel(accountID: UUID) -> CreditCardViewModel {
        CreditCardViewModel(
            accountID: accountID,
            getDetail: DefaultGetCreditCardDetailUseCase(
                accounts: store,
                cards: store,
                transactions: movements,
                categories: store,
                settings: store,
            ),
            updateTerms: DefaultUpdateCreditTermsUseCase(accounts: store),
            setCardColor: DefaultSetCardColorUseCase(cards: store),
            setCardDetails: DefaultSetCardDetailsUseCase(cards: store),
            setCardNumber: DefaultSetCardNumberUseCase(cards: store),
            renameAccount: DefaultRenameAccountUseCase(accounts: store),
            deleteAccount: DefaultDeleteAccountUseCase(accounts: store, cards: store, transactions: movements, recurringRules: store),
            getPreferredName: makeGetPreferredName(),
        )
    }

    // MARK: - Bank account and its card

    func makeDebitCardViewModel(accountID: UUID) -> DebitCardViewModel {
        DebitCardViewModel(
            accountID: accountID,
            getDetail: DefaultGetDebitCardDetailUseCase(
                accounts: store, cards: store, transactions: movements, categories: store, settings: store,
            ),
            setColor: DefaultSetCardColorUseCase(cards: store),
            setDetails: DefaultSetCardDetailsUseCase(cards: store),
            setNumber: DefaultSetCardNumberUseCase(cards: store),
            renameAccount: DefaultRenameAccountUseCase(accounts: store),
            deleteAccount: DefaultDeleteAccountUseCase(accounts: store, cards: store, transactions: movements, recurringRules: store),
            getPreferredName: makeGetPreferredName(),
        )
    }

    // MARK: - Cash

    func makeCashViewModel(accountID: UUID) -> CashViewModel {
        CashViewModel(
            accountID: accountID,
            getDetail: DefaultGetCashDetailUseCase(
                accounts: store,
                cards: store,
                transactions: movements,
                categories: store,
                settings: store,
            ),
            renameAccount: DefaultRenameAccountUseCase(accounts: store),
            deleteAccount: DefaultDeleteAccountUseCase(accounts: store, cards: store, transactions: movements, recurringRules: store),
        )
    }
}
