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

    private let accounts: any AccountRepository
    private let cards: any CardRepository
    private let transactions: any TransactionRepository
    private let categories: any CategoryRepository
    private let settings: any SettingsRepository
    private let recurringRules: (any RecurringRuleRepository)?
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        accounts: any AccountRepository,
        cards: any CardRepository,
        transactions: any TransactionRepository,
        categories: any CategoryRepository,
        settings: any SettingsRepository,
        recurringRules: (any RecurringRuleRepository)? = nil,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now },
    ) {
        self.accounts = accounts
        self.cards = cards
        self.transactions = transactions
        self.categories = categories
        self.settings = settings
        self.recurringRules = recurringRules
        self.calendar = calendar
        self.now = now
    }

    public func execute() async throws(DomainError) -> HomeOverview {
        let stored = try await settings.load() ?? Settings(currencies: .initial)
        let records = try await LedgerRecords.load(accounts: accounts, cards: cards, transactions: transactions, categories: categories)
        let rules = try await recurringRules?.fetchRecurringRules() ?? []
        return try Self.overview(records, rules: rules, settings: stored, calendar: calendar, now: now())
    }

    static func overview(
        _ records: LedgerRecords,
        rules: [RecurringRule] = [],
        settings: Settings,
        calendar: Calendar,
        now: Date,
    ) throws(DomainError) -> HomeOverview {
        let currencies = settings.currencies
        let (accounts, cards, transactions) = (records.accounts, records.cards, records.transactions)
        var allBalances: [Money] = []
        var balances: [HomeOverview.Balance] = []
        var cardDebt = Decimal(0)
        for account in accounts {
            let accountBalances = Balances.balance(of: account, transactions: transactions, calendar: calendar)
            allBalances += accountBalances
            if account.kind == .credit {
                cardDebt += try NetWorth.total(of: accountBalances, settings: currencies).amount
            } else if let balance = accountBalances.first {
                balances.append(HomeOverview.Balance(account: account, balance: balance))
            }
        }
        // Deposits before cash, keeping the order the person created them in.
        balances = balances.filter { $0.account.kind != .cash } + balances.filter { $0.account.kind == .cash }
        let netWorth = try NetWorth.total(of: allBalances, settings: currencies)
        let planned = transactions.filter { !$0.isConfirmed }.sorted { $0.date < $1.date }
        let recent = transactions.filter(\.isConfirmed).sorted { $0.date > $1.date }.prefix(recentCount)

        return HomeOverview(
            settings: currencies,
            netWorth: netWorth,
            netWorthInSecond: NetWorth.inSecondCurrency(netWorth, settings: currencies),
            accountCount: accounts.count { $0.kind != .credit },
            cardCount: cards.count { $0.kind != .transfer },
            month: MonthlySummary(
                month: YearMonth(containing: now, calendar: calendar),
                transactions: transactions,
                currency: currencies.principal,
                calendar: calendar,
            ),
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
            accounts: accounts,
            cards: cards,
            categories: records.categories,
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
