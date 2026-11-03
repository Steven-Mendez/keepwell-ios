import Domain
import Foundation

/// One debit card and the bank account it draws from.
public struct DebitCardDetail: Hashable, Sendable {
    public static let latestCount = 5

    public let card: Card
    public let account: Account
    /// What the account holds; every card on it spends from this one balance.
    public let balance: Money
    /// How many plastics draw from the account, this one included.
    public let cardCount: Int
    /// The account's latest confirmed movements, newest first. The account's rather than the
    /// card's, because the balance above is the account's and has to add up with what's listed;
    /// each row names the card or channel that moved the money.
    public let latestTransactions: [Transaction]
    /// For row subtitles.
    public let accounts: [Account]
    public let cards: [Card]
    public let categories: [TransactionCategory]

    public init(
        card: Card,
        account: Account,
        balance: Money,
        cardCount: Int,
        latestTransactions: [Transaction] = [],
        accounts: [Account] = [],
        cards: [Card] = [],
        categories: [TransactionCategory] = [],
    ) {
        self.card = card
        self.account = account
        self.balance = balance
        self.cardCount = cardCount
        self.latestTransactions = latestTransactions
        self.accounts = accounts
        self.cards = cards
        self.categories = categories
    }
}
