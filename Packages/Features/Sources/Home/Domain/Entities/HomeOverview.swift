import Domain
import Foundation

/// Everything the home screen shows: net worth, the latest movements, this month, planned
/// movements and the balance of each account.
public struct HomeOverview: Hashable, Sendable {
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
    /// Plastics (debit and credit), not transfer channels.
    public let cardCount: Int
    public let month: MonthlySummary
    /// Whether anything was recorded yet; without movements home invites logging the first one.
    public let hasTransactions: Bool
    /// The latest confirmed movements, newest first, so home can show what just happened.
    public let recent: [Transaction]
    /// Planned movements, soonest first.
    public let planned: [Transaction]
    public let plannedSummary: PlannedSummary
    /// Deposits first, then cash.
    public let balances: [Balance]
    /// What every credit card owes, converted to the principal currency (negative). `nil` without cards.
    public let cardDebt: Money?
    /// The three expense categories used most, for the quick-log widget.
    public let frequentExpenseCategoryIDs: [String]
    /// Days before a card's payment day to remind (settings).
    public let paymentReminderDaysBefore: Int
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
        recent: [Transaction],
        planned: [Transaction],
        plannedSummary: PlannedSummary,
        balances: [Balance],
        cardDebt: Money?,
        frequentExpenseCategoryIDs: [String],
        paymentReminderDaysBefore: Int,
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
        self.recent = recent
        self.planned = planned
        self.plannedSummary = plannedSummary
        self.balances = balances
        self.cardDebt = cardDebt
        self.frequentExpenseCategoryIDs = frequentExpenseCategoryIDs
        self.paymentReminderDaysBefore = paymentReminderDaysBefore
        self.accounts = accounts
        self.cards = cards
        self.categories = categories
    }
}
