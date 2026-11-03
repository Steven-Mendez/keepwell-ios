import Domain
import Foundation

/// A bank account and its one debit card, which the person sees as the same thing.
public struct DebitCardDetail: Hashable, Sendable {
    public static let latestCount = 5

    public let card: Card
    public let account: Account
    public let balance: Money
    /// Every movement that touches the account, planned ones included: what deleting it removes.
    public let movementCount: Int
    /// The account's latest confirmed movements, newest first, so they add up with the balance
    /// above; each row names whether the card or a transfer moved the money.
    public let latestTransactions: [Transaction]
    /// For row subtitles.
    public let accounts: [Account]
    public let cards: [Card]
    public let categories: [TransactionCategory]

    public init(
        card: Card,
        account: Account,
        balance: Money,
        movementCount: Int = 0,
        latestTransactions: [Transaction] = [],
        accounts: [Account] = [],
        cards: [Card] = [],
        categories: [TransactionCategory] = [],
    ) {
        self.card = card
        self.account = account
        self.balance = balance
        self.movementCount = movementCount
        self.latestTransactions = latestTransactions
        self.accounts = accounts
        self.cards = cards
        self.categories = categories
    }
}
