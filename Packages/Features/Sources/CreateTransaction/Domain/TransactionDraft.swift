import Domain
import Foundation

/// Where the money comes from: a payment method, or an account without one (cash).
public enum PaymentSource: Hashable, Sendable {
    case card(UUID)
    case account(UUID)
}

/// A movement as the five steps build it.
public struct TransactionDraft: Sendable {
    public var kind: TransactionKind
    public var amount: Decimal
    public var currency: String
    public var categoryID: String?
    public var source: PaymentSource?
    /// Transfers only.
    public var destinationAccountID: UUID?
    public var description: String
    public var date: Date
    public var isPlanned: Bool
    public var isShared: Bool
    /// "USD charged by the bank".
    public var actualDebitedPrincipal: Decimal?
    public var note: String

    public init(
        kind: TransactionKind = .expense,
        amount: Decimal = 0,
        currency: String,
        categoryID: String? = nil,
        source: PaymentSource? = nil,
        destinationAccountID: UUID? = nil,
        description: String = "",
        date: Date = .now,
        isPlanned: Bool = false,
        isShared: Bool = false,
        actualDebitedPrincipal: Decimal? = nil,
        note: String = "",
    ) {
        self.kind = kind
        self.amount = amount
        self.currency = currency
        self.categoryID = categoryID
        self.source = source
        self.destinationAccountID = destinationAccountID
        self.description = description
        self.date = date
        self.isPlanned = isPlanned
        self.isShared = isShared
        self.actualDebitedPrincipal = actualDebitedPrincipal
        self.note = note
    }
}

/// Everything the flow shows while building a movement.
public struct TransactionContext: Sendable {
    public let currencies: CurrencySettings
    public let categories: [TransactionCategory]
    public let accounts: [Account]
    public let cards: [Card]
    public let balances: [UUID: [Money]]
    /// When each payment source was last used, for ordering and "Used 2 days ago".
    public let lastUsed: [PaymentSource: Date]
    /// How many movements each category has, to put the usual ones first.
    public let categoryUsage: [String: Int]
    /// Cap usage of additional cards in their current cycle.
    public let additionalUsage: [UUID: AdditionalCardUsage]

    public init(
        currencies: CurrencySettings,
        categories: [TransactionCategory],
        accounts: [Account],
        cards: [Card],
        balances: [UUID: [Money]],
        lastUsed: [PaymentSource: Date],
        categoryUsage: [String: Int],
        additionalUsage: [UUID: AdditionalCardUsage],
    ) {
        self.currencies = currencies
        self.categories = categories
        self.accounts = accounts
        self.cards = cards
        self.balances = balances
        self.lastUsed = lastUsed
        self.categoryUsage = categoryUsage
        self.additionalUsage = additionalUsage
    }

    public func account(_ id: UUID?) -> Account? {
        accounts.first { $0.id == id }
    }

    public func card(_ id: UUID?) -> Card? {
        cards.first { $0.id == id }
    }

    /// The account a source draws from (rule 3: derived from the payment method).
    public func accountID(for source: PaymentSource) -> UUID? {
        switch source {
        case let .card(id): card(id)?.accountID
        case let .account(id): id
        }
    }

    /// The most recently used source, the flow's default.
    public var lastUsedSource: PaymentSource? {
        lastUsed.max { $0.value < $1.value }?.key
    }
}

/// What the saved screen shows.
public struct SavedTransaction: Sendable {
    public let transaction: Transaction
    public let account: Account
    /// The source account's balances after the movement (planned movements leave them unchanged).
    public let newBalances: [Money]
    /// Spending in the movement's category this month, in the principal currency.
    public let categoryMonthTotal: Money?

    public init(transaction: Transaction, account: Account, newBalances: [Money], categoryMonthTotal: Money?) {
        self.transaction = transaction
        self.account = account
        self.newBalances = newBalances
        self.categoryMonthTotal = categoryMonthTotal
    }
}
