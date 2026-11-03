import Domain
import Foundation

public protocol GetDebitCardDetailUseCase: Sendable {
    func execute(cardID: UUID) async throws(DomainError) -> DebitCardDetail
}

public struct DefaultGetDebitCardDetailUseCase: GetDebitCardDetailUseCase {
    private let accounts: any AccountRepository
    private let cards: any CardRepository
    private let transactions: any TransactionRepository
    private let settings: any SettingsRepository
    private let calendar: Calendar

    public init(
        accounts: any AccountRepository,
        cards: any CardRepository,
        transactions: any TransactionRepository,
        settings: any SettingsRepository,
        calendar: Calendar = .current,
    ) {
        self.accounts = accounts
        self.cards = cards
        self.transactions = transactions
        self.settings = settings
        self.calendar = calendar
    }

    public func execute(cardID: UUID) async throws(DomainError) -> DebitCardDetail {
        let allCards = try await cards.fetchCards()
        guard let card = allCards.first(where: { $0.id == cardID && $0.kind == .debit }) else {
            throw .notFound(cardID)
        }
        guard let account = try await accounts.fetchAccounts().first(where: { $0.id == card.accountID }) else {
            throw .notFound(card.accountID)
        }
        let principal = try await settings.load()?.currencies.principal ?? CurrencySettings.fallback.principal
        let movements = try await transactions.fetchTransactions(in: nil)
        let balance = Balances.balance(of: account, transactions: movements, calendar: calendar).first ?? .zero(principal)
        return DebitCardDetail(
            card: card,
            account: account,
            balance: balance,
            cardCount: allCards.count { $0.accountID == account.id && $0.kind == .debit },
        )
    }
}
