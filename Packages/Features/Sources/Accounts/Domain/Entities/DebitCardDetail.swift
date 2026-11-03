import Domain
import Foundation

/// One debit card and the bank account it draws from.
public struct DebitCardDetail: Hashable, Sendable {
    public let card: Card
    public let account: Account
    /// What the account holds; every card on it spends from this one balance.
    public let balance: Money
    /// How many plastics draw from the account, this one included.
    public let cardCount: Int

    public init(card: Card, account: Account, balance: Money, cardCount: Int) {
        self.card = card
        self.account = account
        self.balance = balance
        self.cardCount = cardCount
    }
}
