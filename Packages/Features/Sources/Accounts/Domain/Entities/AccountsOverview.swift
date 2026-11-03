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
        /// The account's one card, its face on screen. `nil` only for the moment between a sync
        /// bringing an account and the launch check giving it its card.
        public let debitCard: Card?
        public var id: UUID { account.id }

        public init(account: Account, balance: Money, debitCard: Card?) {
            self.account = account
            self.balance = balance
            self.debitCard = debitCard
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
