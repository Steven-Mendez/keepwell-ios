import AccountsDomain
import AccountsPresentation
import CreditCardDomain
import CreditCardPresentation
import Domain
import Foundation
import SharedPresentation

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
            closing: makeAccountClosing(accountID: accountID),
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
            closing: makeAccountClosing(accountID: accountID),
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
            closing: makeAccountClosing(accountID: accountID),
        )
    }

    // MARK: - Closing

    /// "Close account" and "Reopen" on any of the three screens.
    func makeAccountClosing(accountID: UUID) -> AccountClosingModel {
        let closing = DefaultAccountClosingUseCase(
            accounts: store, cards: store, transactions: movements, recurringRules: store, settings: store,
        )
        return AccountClosingModel(accountID: accountID, getPlan: closing, close: closing, reopen: closing)
    }
}
