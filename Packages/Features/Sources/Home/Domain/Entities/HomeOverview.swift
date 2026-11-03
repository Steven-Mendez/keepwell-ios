import Domain
import Foundation

/// Everything the home screen shows: net worth, this month, planned movements, additional cards
/// close to their cap and the balance of each account.
public struct HomeOverview: Hashable, Sendable {
    public struct AdditionalCardStatus: Identifiable, Hashable, Sendable {
        public let card: Card
        /// The credit account the additional belongs to.
        public let account: Account
        /// The holder plastic, for the card's network and digits.
        public let holder: Card?
        public let usage: AdditionalCardUsage
        public var id: UUID { card.id }
    }

    public struct Balance: Identifiable, Hashable, Sendable {
        public let account: Account
        public let balance: Money
        public var id: UUID { account.id }
    }

    public let settings: CurrencySettings
    public let netWorth: Money
    /// The net worth in the second currency, when there is one.
    public let netWorthInSecond: Money?
    /// Deposit and cash accounts.
    public let accountCount: Int
    /// Plastics (debit, holder and additional), not transfer channels.
    public let cardCount: Int
    public let month: MonthlySummary
    /// Whether anything was recorded yet; without movements home invites logging the first one.
    public let hasTransactions: Bool
    /// Planned movements, soonest first.
    public let planned: [Transaction]
    public let plannedSummary: PlannedSummary
    /// Additional cards with a cycle cap.
    public let additionalCards: [AdditionalCardStatus]
    /// Deposits first, then cash.
    public let balances: [Balance]
    /// What every credit card owes, converted to the principal currency (negative). `nil` without cards.
    public let cardDebt: Money?
    /// The three expense categories used most, for the quick-log widget.
    public let frequentExpenseCategoryIDs: [String]
    /// Days before a card's payment day to remind (settings).
    public let paymentReminderDaysBefore: Int
    /// Fraction of an additional card's cap that triggers its alert (settings).
    public let capAlertThreshold: Decimal
    /// For row subtitles.
    public let accounts: [Account]
    public let cards: [Card]
    public let categories: [TransactionCategory]

    public init(
        settings: CurrencySettings,
        netWorth: Money,
        netWorthInSecond: Money?,
        accountCount: Int,
        cardCount: Int,
        month: MonthlySummary,
        hasTransactions: Bool,
        planned: [Transaction],
        plannedSummary: PlannedSummary,
        additionalCards: [AdditionalCardStatus],
        balances: [Balance],
        cardDebt: Money?,
        frequentExpenseCategoryIDs: [String],
        paymentReminderDaysBefore: Int,
        capAlertThreshold: Decimal,
        accounts: [Account],
        cards: [Card],
        categories: [TransactionCategory],
    ) {
        self.settings = settings
        self.netWorth = netWorth
        self.netWorthInSecond = netWorthInSecond
        self.accountCount = accountCount
        self.cardCount = cardCount
        self.month = month
        self.hasTransactions = hasTransactions
        self.planned = planned
        self.plannedSummary = plannedSummary
        self.additionalCards = additionalCards
        self.balances = balances
        self.cardDebt = cardDebt
        self.frequentExpenseCategoryIDs = frequentExpenseCategoryIDs
        self.paymentReminderDaysBefore = paymentReminderDaysBefore
        self.capAlertThreshold = capAlertThreshold
        self.accounts = accounts
        self.cards = cards
        self.categories = categories
    }
}
