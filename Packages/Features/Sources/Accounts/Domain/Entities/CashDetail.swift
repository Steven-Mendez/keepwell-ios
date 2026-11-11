import Domain
import Foundation

/// A cash account: its balance, latest movements and what deleting it would remove.
public struct CashDetail: Hashable, Sendable {
    public static let latestCount = 5

    public let account: Account
    public let balance: Money
    /// The balance in the principal currency when the cash is in another one.
    public let principalEquivalent: Money?
    /// Every movement that touches the account, planned ones included: what deleting it removes.
    public let movementCount: Int
    /// The account's latest confirmed movements, newest first.
    public let latestTransactions: [Transaction]
    /// For row subtitles.
    public let accounts: [Account]
    public let cards: [Card]
    public let categories: [TransactionCategory]

    public init(
        account: Account,
        balance: Money,
        principalEquivalent: Money? = nil,
        movementCount: Int = 0,
        latestTransactions: [Transaction] = [],
        accounts: [Account] = [],
        cards: [Card] = [],
        categories: [TransactionCategory] = [],
    ) {
        self.account = account
        self.balance = balance
        self.principalEquivalent = principalEquivalent
        self.movementCount = movementCount
        self.latestTransactions = latestTransactions
        self.accounts = accounts
        self.cards = cards
        self.categories = categories
    }
}
