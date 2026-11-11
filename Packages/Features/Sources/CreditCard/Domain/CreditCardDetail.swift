import Domain
import Foundation

/// One credit card: its debt, billing data and this cycle's movements.
public struct CreditCardDetail: Hashable, Sendable {
    public let account: Account
    /// The plastic: network, digits and art.
    public let holder: Card?
    /// Debt per currency, negative, in the order the account holds them.
    public let balances: [Money]
    /// The whole debt in the principal currency (negative).
    public let totalDebt: Money
    /// Limit minus what's owed, in the limit's currency. `nil` without a limit.
    public let available: Money?
    public let cycle: DateInterval?
    /// Confirmed and planned movements charged to the card in the current cycle, newest first.
    public let cycleTransactions: [Transaction]
    public let nextCutoff: Date?
    public let nextDue: Date?
    /// Every movement that touches the account, planned ones included: what deleting it removes.
    public let movementCount: Int
    public let settings: CurrencySettings
    /// For row subtitles.
    public let accounts: [Account]
    public let cards: [Card]
    public let categories: [TransactionCategory]

    public init(
        account: Account,
        holder: Card?,
        balances: [Money],
        totalDebt: Money,
        available: Money?,
        cycle: DateInterval?,
        cycleTransactions: [Transaction],
        nextCutoff: Date?,
        nextDue: Date?,
        movementCount: Int = 0,
        settings: CurrencySettings,
        accounts: [Account],
        cards: [Card],
        categories: [TransactionCategory],
    ) {
        self.account = account
        self.holder = holder
        self.balances = balances
        self.totalDebt = totalDebt
        self.available = available
        self.cycle = cycle
        self.cycleTransactions = cycleTransactions
        self.nextCutoff = nextCutoff
        self.nextDue = nextDue
        self.movementCount = movementCount
        self.settings = settings
        self.accounts = accounts
        self.cards = cards
        self.categories = categories
    }

    /// The whole debt is only worth showing when every currency owed converts at the current rate:
    /// otherwise it would silently leave one out, or sum currencies without a rate.
    public var showsTotalDebt: Bool {
        balances.count > 1 && balances.allSatisfy { (try? settings.exchangeRate.convert($0, to: settings.principal)) != nil }
    }

    /// The currency the limit is kept in: the one it was set in, the second currency for a card
    /// that only charges in it, otherwise the principal one.
    public var limitCurrency: String {
        account.creditTerms?.limit?.currency ?? (account.creditTerms?.debtMode == .second ? settings.second : nil) ?? settings.principal
    }
}

public protocol GetCreditCardDetailUseCase: Sendable {
    func execute(accountID: UUID) async throws(DomainError) -> CreditCardDetail
}

public struct DefaultGetCreditCardDetailUseCase: GetCreditCardDetailUseCase {
    private let accounts: any AccountRepository
    private let cards: any CardRepository
    private let transactions: any TransactionRepository
    private let categories: any CategoryRepository
    private let settings: any SettingsRepository
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        accounts: any AccountRepository,
        cards: any CardRepository,
        transactions: any TransactionRepository,
        categories: any CategoryRepository,
        settings: any SettingsRepository,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now },
    ) {
        self.accounts = accounts
        self.cards = cards
        self.transactions = transactions
        self.categories = categories
        self.settings = settings
        self.calendar = calendar
        self.now = now
    }

    public func execute(accountID: UUID) async throws(DomainError) -> CreditCardDetail {
        let stored = try await settings.load() ?? Settings(currencies: .initial)
        let records = try await LedgerRecords.load(accounts: accounts, cards: cards, transactions: transactions, categories: categories)
        return try Self.detail(accountID: accountID, records: records, settings: stored, calendar: calendar, now: now())
    }

    static func detail(
        accountID: UUID,
        records: LedgerRecords,
        settings: Settings,
        calendar: Calendar,
        now: Date,
    ) throws(DomainError) -> CreditCardDetail {
        let (accounts, cards, transactions, categories) = (records.accounts, records.cards, records.transactions, records.categories)
        guard let account = accounts.first(where: { $0.id == accountID && $0.kind == .credit }) else {
            throw .notFound(accountID)
        }
        let currencies = settings.currencies
        let accountCards = cards.filter { $0.accountID == accountID }
        let balances = Balances.balance(of: account, transactions: transactions, calendar: calendar)
        let totalDebt = try NetWorth.total(of: balances, settings: currencies)
        let terms = account.creditTerms
        let cycle = BillingCycle.cycle(containing: now, cutoffDay: terms?.cutoffDay, calendar: calendar)

        var available: Money?
        // A limit in a currency the settings no longer convert: no "available" rather than a wrong one.
        if let limit = terms?.limit, let owed = try? currencies.exchangeRate.convert(totalDebt, to: limit.currency) {
            available = Money(limit.amount + owed.amount, limit.currency)
        }
        let cycleTransactions = transactions
            .filter { transaction in
                transaction.accountID == accountID && cycle.map { transaction.date >= $0.start && transaction.date < $0.end } ?? true
            }
            .sorted { $0.date > $1.date }

        return CreditCardDetail(
            account: account,
            holder: accountCards.first { $0.kind == .creditHolder },
            balances: balances,
            totalDebt: totalDebt,
            available: available,
            cycle: cycle,
            cycleTransactions: cycleTransactions,
            nextCutoff: terms?.cutoffDay.flatMap { BillingCycle.nextOccurrence(ofDay: $0, onOrAfter: now, calendar: calendar) },
            nextDue: terms?.dueDay.flatMap { BillingCycle.nextOccurrence(ofDay: $0, onOrAfter: now, calendar: calendar) },
            movementCount: transactions.count { TransactionScope.account(accountID).includes($0) },
            settings: currencies,
            accounts: accounts,
            cards: cards,
            categories: categories,
        )
    }
}
