import Domain
import Foundation

/// Where the money comes from: a payment method, or an account without one (cash).
public enum PaymentSource: Hashable, Sendable {
    case card(UUID)
    case account(UUID)
}

extension PaymentSource {
    var cardID: UUID? {
        if case let .card(id) = self {
            return id
        }
        return nil
    }
}

/// A movement as the five steps build it.
public struct TransactionDraft: Sendable {
    /// Chosen when the flow starts, so the receipt can show its reference before anything reloads.
    public var id: UUID
    public var kind: TransactionKind
    public var amount: Decimal
    public var currency: String
    public var categoryID: String?
    public var source: PaymentSource?
    /// Transfers only.
    public var destinationAccountID: UUID?
    public var description: String
    public var date: Date
    /// "USD charged by the bank".
    public var actualDebitedPrincipal: Decimal?
    public var note: String

    public init(
        id: UUID = UUID(),
        kind: TransactionKind = .expense,
        amount: Decimal = 0,
        currency: String,
        categoryID: String? = nil,
        source: PaymentSource? = nil,
        destinationAccountID: UUID? = nil,
        description: String = "",
        date: Date = .now,
        actualDebitedPrincipal: Decimal? = nil,
        note: String = "",
    ) {
        self.id = id
        self.kind = kind
        self.amount = amount
        self.currency = currency
        self.categoryID = categoryID
        self.source = source
        self.destinationAccountID = destinationAccountID
        self.description = description
        self.date = date
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

    /// The same context with a category the person just created, so the flow can pick it without
    /// reloading and losing the currency and payment method already chosen.
    public func adding(_ category: TransactionCategory) -> Self {
        Self(
            currencies: currencies,
            categories: categories.filter { $0.id != category.id } + [category],
            accounts: accounts,
            cards: cards,
            balances: balances,
            lastUsed: lastUsed,
            categoryUsage: categoryUsage,
            additionalUsage: additionalUsage,
        )
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
    /// The source account's balances after the movement.
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
