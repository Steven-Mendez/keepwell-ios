import Domain
import Foundation

public protocol GetHomeOverviewUseCase: Sendable {
    func execute() async throws(DomainError) -> HomeOverview
}

public struct DefaultGetHomeOverviewUseCase: GetHomeOverviewUseCase {
    /// How many confirmed movements home previews before "See all".
    static let recentCount = 3
    /// How far ahead recurring occurrences are listed (home shows a week; reminders use the rest).
    static let upcomingDays = 30
    /// How far ahead home's "Upcoming" card looks.
    static let upcomingPaymentDays = 7

    private let accounts: any AccountRepository
    private let cards: any CardRepository
    private let transactions: any TransactionRepository
    private let categories: any CategoryRepository
    private let settings: any SettingsRepository
    private let recurringRules: (any RecurringRuleRepository)?
    private let savingsGoals: (any SavingsGoalRepository)?
    private let loans: (any LoanRepository)?
    private let personalDebts: (any PersonalDebtRepository)?
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        accounts: any AccountRepository,
        cards: any CardRepository,
        transactions: any TransactionRepository,
        categories: any CategoryRepository,
        settings: any SettingsRepository,
        recurringRules: (any RecurringRuleRepository)? = nil,
        savingsGoals: (any SavingsGoalRepository)? = nil,
        loans: (any LoanRepository)? = nil,
        personalDebts: (any PersonalDebtRepository)? = nil,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now },
    ) {
        self.accounts = accounts
        self.cards = cards
        self.transactions = transactions
        self.categories = categories
        self.settings = settings
        self.recurringRules = recurringRules
        self.savingsGoals = savingsGoals
        self.loans = loans
        self.personalDebts = personalDebts
        self.calendar = calendar
        self.now = now
    }

    public func execute() async throws(DomainError) -> HomeOverview {
        let stored = try await settings.load() ?? Settings(currencies: .initial)
        let records = try await LedgerRecords.load(accounts: accounts, cards: cards, transactions: transactions, categories: categories)
        let rules = try await recurringRules?.fetchRecurringRules() ?? []
        let goals = try await savingsGoals?.fetchSavingsGoals() ?? []
        let loanRows = try await loans?.fetchLoans() ?? []
        let personalRows = try await personalDebts?.fetchPersonalDebts() ?? []
        let deposits = try await personalDebts?.fetchRepaymentDepositIDs() ?? []
        let debts = DebtRecords(loans: loanRows, personal: personalRows, deposits: deposits)
        return try Self.overview(records, rules: rules, goals: goals, debts: debts, settings: stored, calendar: calendar, now: now())
    }

    static func overview(
        _ records: LedgerRecords,
        rules: [RecurringRule] = [],
        goals: [SavingsGoal] = [],
        debts: DebtRecords = DebtRecords(),
        settings: Settings,
        calendar: Calendar,
        now: Date,
    ) throws(DomainError) -> HomeOverview {
        let currencies = settings.currencies
        let (accounts, cards, transactions) = (records.accounts, records.cards, records.transactions)
        let (allBalances, balances, cardDebt) = try accountBalances(records, settings: currencies, calendar: calendar)
        let netWorth = try NetWorth.total(of: allBalances, settings: currencies)
        let planned = transactions.filter { !$0.isConfirmed }.sorted { $0.date < $1.date }
        let recent = transactions.filter(\.isConfirmed).sorted { $0.date > $1.date }.prefix(recentCount)
        // Split expenses count only the person's part, here and in the budgets and forecast; deposits
        // of deleted debts still aren't income.
        let links = DebtLinks(debts.personal, deposits: debts.deposits)
        let month = MonthlySummary(
            month: YearMonth(containing: now, calendar: calendar), transactions: transactions, currency: currencies.principal,
            calendar: calendar, debts: links,
        )

        return HomeOverview(
            settings: currencies,
            netWorth: netWorth,
            netWorthInSecond: NetWorth.inSecondCurrency(netWorth, settings: currencies),
            netWorthExcluded: NetWorth.excludedCurrencies(of: allBalances, settings: currencies),
            // Lists and counts show open accounts; the totals above still add up every one.
            accountCount: accounts.count { $0.kind != .credit && $0.isOpen },
            cardCount: cards.count { card in card.kind != .transfer && accounts.open.contains { $0.id == card.accountID } },
            month: month,
            hasTransactions: !transactions.isEmpty,
            recent: Array(recent),
            planned: planned,
            plannedSummary: PlannedSummary(transactions: planned),
            balances: balances,
            cardDebt: accounts.contains { $0.kind == .credit } ? Money(cardDebt, currencies.principal) : nil,
            frequentExpenseCategoryIDs: frequentExpenseCategories(records),
            paymentReminderDaysBefore: settings.paymentReminderDaysBefore,
            cardSubscriptions: cardSubscriptions(records, rules: rules, calendar: calendar),
            upcoming: RecurringSchedule.upcoming(rules, from: now, days: upcomingDays, calendar: calendar),
            upcomingPayments: upcomingPayments(
                records,
                rules: rules,
                debts: debts,
                settings: currencies,
                at: (now, calendar),
            ),
            proposedRules: rules.filter { $0.source == .mcp && $0.isPaused },
            budgets: CategoryBudgetStatus.statuses(of: month, categories: records.categories),
            latestExpenseDays: latestExpenseDays(transactions, month: month.month, calendar: calendar, now: now),
            goals: SavingsGoalProgress.ordered(goals, currentMonth: month.month),
            forecast: forecast(records, rules: rules, settings: currencies, debts: links, at: (now, calendar)),
            priceIncreases: PriceIncrease.detect(in: transactions, now: now, calendar: calendar),
            loans: LoanProgress.ordered(debts.loans, today: now, calendar: calendar),
            debtTotals: DebtTotals(loans: debts.loans, debts: debts.personal),
            personalDebts: debts.personal,
            accounts: accounts,
            cards: cards,
            categories: records.categories,
        )
    }

    /// What home's "Upcoming" card and its status line read.
    private static func upcomingPayments(
        _ records: LedgerRecords,
        rules: [RecurringRule],
        debts: DebtRecords,
        settings: CurrencySettings,
        at moment: (now: Date, calendar: Calendar),
    ) -> [UpcomingPayment] {
        let ledger = UpcomingPayments.Ledger(
            transactions: records.transactions,
            rules: rules,
            accounts: records.accounts,
            loans: debts.loans,
            personalDebts: debts.personal,
            settings: settings,
        )
        return UpcomingPayments.compute(ledger, on: moment.now, days: upcomingPaymentDays, calendar: moment.calendar)
    }

    /// When each category was last spent in this month, up to now.
    private static func latestExpenseDays(
        _ transactions: [Transaction],
        month: YearMonth,
        calendar: Calendar,
        now: Date,
    ) -> [String: Date] {
        var latest: [String: Date] = [:]
        for transaction in transactions where transaction.kind == .expense && transaction.date <= now {
            guard let category = transaction.categoryID,
                  YearMonth(containing: transaction.date, calendar: calendar) == month else { continue }
            if latest[category].map({ $0 < transaction.date }) ?? true {
                latest[category] = transaction.date
            }
        }
        return latest
    }

    /// Every balance (for net worth), the bank and cash ones shown on home, and what the cards owe in
    /// the principal currency.
    private static func accountBalances(
        _ records: LedgerRecords,
        settings currencies: CurrencySettings,
        calendar: Calendar,
    ) throws(DomainError) -> ([Money], [HomeOverview.Balance], Decimal) {
        var allBalances: [Money] = []
        var balances: [HomeOverview.Balance] = []
        var cardDebt = Decimal(0)
        for account in records.accounts {
            let accountBalances = Balances.balance(of: account, transactions: records.transactions, calendar: calendar)
            allBalances += accountBalances
            if account.kind == .credit {
                cardDebt += try NetWorth.total(of: accountBalances, settings: currencies).amount
            } else if account.isOpen, let balance = accountBalances.first {
                balances.append(HomeOverview.Balance(account: account, balance: balance))
            }
        }
        // Deposits before cash, keeping the order the person created them in.
        balances = balances.filter { $0.account.kind != .cash } + balances.filter { $0.account.kind == .cash }
        return (allBalances, balances, cardDebt)
    }

    /// Only with a bank or cash account: the forecast is about the money that can be spent.
    private static func forecast(
        _ records: LedgerRecords,
        rules: [RecurringRule],
        settings: CurrencySettings,
        debts: DebtLinks,
        at moment: (now: Date, calendar: Calendar),
    ) -> BalanceForecast? {
        guard records.accounts.contains(where: { $0.kind != .credit }) else { return nil }
        return BalanceForecast(
            accounts: records.accounts,
            transactions: records.transactions,
            rules: rules,
            settings: settings,
            now: moment.now,
            calendar: moment.calendar,
            debts: debts,
        )
    }

    /// Only plastics with an expiry: the reminder is the one place that lists them.
    private static func cardSubscriptions(_ records: LedgerRecords, rules: [RecurringRule], calendar: Calendar) -> [UUID: [String]] {
        records.cards.filter { $0.expiry != nil }.reduce(into: [:]) { result, card in
            result[card.id] = Subscriptions.charged(toCard: card.id, transactions: records.transactions, rules: rules, calendar: calendar)
        }
    }

    /// Expense categories by how often they're used, most first; ties keep the default order.
    private static func frequentExpenseCategories(_ records: LedgerRecords) -> [String] {
        let usage = records.transactions.reduce(into: [String: Int]()) { counts, transaction in
            if transaction.kind == .expense, let id = transaction.categoryID {
                counts[id, default: 0] += 1
            }
        }
        let expense = records.categories.filter { $0.kind == .expense }.map(\.id)
        return expense.enumerated()
            .sorted { (usage[$0.element] ?? 0, -$0.offset) > (usage[$1.element] ?? 0, -$1.offset) }
            .prefix(3)
            .map(\.element)
    }
}

/// Loans and personal debts as home reads them, together so `overview` keeps one parameter for both.
struct DebtRecords {
    var loans: [Loan] = []
    var personal: [PersonalDebt] = []
    /// Every movement a repayment deposited, deleted debts' included.
    var deposits: [UUID] = []
}
