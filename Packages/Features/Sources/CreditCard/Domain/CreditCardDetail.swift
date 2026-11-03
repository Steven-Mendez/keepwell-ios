import Domain
import Foundation

/// One credit card: its debt, billing data, plastics and this cycle's movements.
public struct CreditCardDetail: Hashable, Sendable {
    public struct Additional: Identifiable, Hashable, Sendable {
        public let card: Card
        /// Spending against the cap in the current cycle.
        public let usage: AdditionalCardUsage
        public var id: UUID { card.id }
    }

    public let account: Account
    /// The holder plastic: network, digits and art.
    public let holder: Card?
    public let additionals: [Additional]
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
    public let settings: CurrencySettings
    /// Fraction of a cap that triggers the alert (settings).
    public let capAlertThreshold: Decimal
    /// For row subtitles and the allowed-category chips.
    public let accounts: [Account]
    public let cards: [Card]
    public let categories: [TransactionCategory]

    public init(
        account: Account,
        holder: Card?,
        additionals: [Additional],
        balances: [Money],
        totalDebt: Money,
        available: Money?,
        cycle: DateInterval?,
        cycleTransactions: [Transaction],
        nextCutoff: Date?,
        nextDue: Date?,
        settings: CurrencySettings,
        capAlertThreshold: Decimal,
        accounts: [Account],
        cards: [Card],
        categories: [TransactionCategory],
    ) {
        self.account = account
        self.holder = holder
        self.additionals = additionals
        self.balances = balances
        self.totalDebt = totalDebt
        self.available = available
        self.cycle = cycle
        self.cycleTransactions = cycleTransactions
        self.nextCutoff = nextCutoff
        self.nextDue = nextDue
        self.settings = settings
        self.capAlertThreshold = capAlertThreshold
        self.accounts = accounts
        self.cards = cards
        self.categories = categories
    }

    public func additional(id: UUID) -> Additional? {
        additionals.first { $0.id == id }
    }

    /// The currency the limit and caps are kept in: the card's only currency, or the principal
    /// one for a dual card.
    /// The currency additional cards are capped in: the local one on a two-currency card, since
    /// additionals are mostly for local spending; otherwise the card's own currency.
    public var capCurrency: String {
        account.currencies.count > 1 ? (settings.second ?? settings.principal) : (account.currencies.first ?? settings.principal)
    }

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
        if let limit = terms?.limit {
            let owed = try currencies.exchangeRate.convert(totalDebt, to: limit.currency)
            available = Money(limit.amount + owed.amount, limit.currency)
        }
        let additionals = accountCards.filter { $0.kind == .creditAdditional }.map { card in
            CreditCardDetail.Additional(
                card: card,
                usage: cycle.map { AdditionalCardUsage(
                    card: card,
                    transactions: transactions,
                    cycle: $0,
                    fallbackCurrency: currencies.principal,
                ) }
                    ?? AdditionalCardUsage(card: card, transactions: [], cycle: DateInterval(), fallbackCurrency: currencies.principal),
            )
        }
        let cycleTransactions = transactions
            .filter { transaction in
                transaction.accountID == accountID && cycle.map { transaction.date >= $0.start && transaction.date < $0.end } ?? true
            }
            .sorted { $0.date > $1.date }

        return CreditCardDetail(
            account: account,
            holder: accountCards.first { $0.kind == .creditHolder },
            additionals: additionals,
            balances: balances,
            totalDebt: totalDebt,
            available: available,
            cycle: cycle,
            cycleTransactions: cycleTransactions,
            nextCutoff: terms?.cutoffDay.flatMap { BillingCycle.nextOccurrence(ofDay: $0, onOrAfter: now, calendar: calendar) },
            nextDue: terms?.dueDay.flatMap { BillingCycle.nextOccurrence(ofDay: $0, onOrAfter: now, calendar: calendar) },
            settings: currencies,
            capAlertThreshold: settings.additionalCapAlertThreshold,
            accounts: accounts,
            cards: cards,
            categories: categories,
        )
    }
}
