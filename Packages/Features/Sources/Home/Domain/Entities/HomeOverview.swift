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
    /// Currencies with a balance that net worth leaves out because the settings can't convert them.
    public let netWorthExcluded: [String]
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
    /// Services charged to each plastic again and again, by card id, for the expiry reminder.
    public let cardSubscriptions: [UUID: [String]]
    /// Recurring occurrences from today through the next 30 days, soonest first.
    public let upcoming: [RecurringOccurrence]
    /// What's pending through the next week, overdue first: drafts, recurring occurrences, card
    /// payments and loan installments. Home's "Upcoming" card and its status line read it.
    public let upcomingPayments: [UpcomingPayment]
    /// Recurring rules an assistant created, paused until the person confirms or discards them.
    public let proposedRules: [RecurringRule]
    /// This month's budgeted categories, closest to their limit first.
    public let budgets: [CategoryBudgetStatus]
    /// The day of the latest expense up to now in each category this month, which dates a budget's
    /// notification. Absent for categories with none.
    public let latestExpenseDays: [String: Date]
    /// Savings goals in list order (the first is the one home previews).
    public let goals: [SavingsGoalProgress]
    /// Roughly what the bank and cash accounts will hold at the end of this month. `nil` without
    /// any such account.
    public let forecast: BalanceForecast?
    /// Subscriptions whose latest charge cost more than the one before, newest first.
    public let priceIncreases: [PriceIncrease]
    /// Loans in list order: the first open one has the next installment due.
    public let loans: [LoanProgress]
    /// "You owe" and "Owed to you" per currency, loans and personal debts together.
    public let debtTotals: DebtTotals
    /// For row subtitles.
    public let accounts: [Account]
    public let cards: [Card]
    public let categories: [TransactionCategory]

    public init(
        settings: CurrencySettings,
        netWorth: Money,
        netWorthInSecond: Money?,
        netWorthExcluded: [String] = [],
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
        cardSubscriptions: [UUID: [String]] = [:],
        upcoming: [RecurringOccurrence] = [],
        upcomingPayments: [UpcomingPayment] = [],
        proposedRules: [RecurringRule] = [],
        budgets: [CategoryBudgetStatus] = [],
        latestExpenseDays: [String: Date] = [:],
        goals: [SavingsGoalProgress] = [],
        forecast: BalanceForecast? = nil,
        priceIncreases: [PriceIncrease] = [],
        loans: [LoanProgress] = [],
        debtTotals: DebtTotals = DebtTotals(loans: [], debts: []),
        accounts: [Account],
        cards: [Card],
        categories: [TransactionCategory],
    ) {
        self.settings = settings
        self.netWorth = netWorth
        self.netWorthInSecond = netWorthInSecond
        self.netWorthExcluded = netWorthExcluded
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
        self.cardSubscriptions = cardSubscriptions
        self.upcoming = upcoming
        self.upcomingPayments = upcomingPayments
        self.proposedRules = proposedRules
        self.budgets = budgets
        self.latestExpenseDays = latestExpenseDays
        self.goals = goals
        self.forecast = forecast
        self.priceIncreases = priceIncreases
        self.loans = loans
        self.debtTotals = debtTotals
        self.accounts = accounts
        self.cards = cards
        self.categories = categories
    }
}
