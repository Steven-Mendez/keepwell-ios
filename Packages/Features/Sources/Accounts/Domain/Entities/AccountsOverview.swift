import Domain
import Foundation

/// Everything the accounts screen shows, computed from accounts, cards and confirmed movements.
public struct AccountsOverview: Hashable, Sendable {
    public struct CreditCard: Identifiable, Hashable, Sendable {
        public let account: Account
        /// The holder plastic, which gives the card its art, network and digits.
        public let holder: Card?
        public let plasticCount: Int
        /// Debts per currency, negative, second currency first as the cards show them.
        public let balances: [Money]
        public var id: UUID { account.id }
    }

    public struct Deposit: Identifiable, Hashable, Sendable {
        public let account: Account
        public let balance: Money
        /// The plastics that draw from this account. Its transfer channel is left out: the screen
        /// shows accounts through their cards, and moving money between accounts is a transfer
        /// movement, not something the person links.
        public let debitCards: [Card]
        public var id: UUID { account.id }

        public init(account: Account, balance: Money, debitCards: [Card]) {
            self.account = account
            self.balance = balance
            self.debitCards = debitCards
        }
    }

    public struct Cash: Identifiable, Hashable, Sendable {
        public let account: Account
        public let balance: Money
        /// The balance in the principal currency when the cash is in another one.
        public let principalEquivalent: Money?
        public var id: UUID { account.id }
    }

    public let settings: CurrencySettings
    public let netWorth: Money
    public let creditCards: [CreditCard]
    public let deposits: [Deposit]
    public let cash: [Cash]

    public init(settings: CurrencySettings, netWorth: Money, creditCards: [CreditCard], deposits: [Deposit], cash: [Cash]) {
        self.settings = settings
        self.netWorth = netWorth
        self.creditCards = creditCards
        self.deposits = deposits
        self.cash = cash
    }
}
