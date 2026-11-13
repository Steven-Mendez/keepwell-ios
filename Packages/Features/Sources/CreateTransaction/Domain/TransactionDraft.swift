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
    /// What a charge carried over from a saved movement (`init(editing:)`) was charged for: the
    /// amount, currency and account it was recorded with. Once any of them changes that charge no
    /// longer applies, so the movement saves without it (`applicableDebit`). A charge typed for the
    /// draft leaves this out.
    public var debitedFor: DebitedFor?
    public var note: String
    /// Saved without counting toward balances until the person confirms it.
    public var isDraft: Bool
    /// "Repeat": also saves a recurring rule from this movement, every week, month or year.
    public var repeatFrequency: RecurringFrequency?
    /// The id the recurring rule gets when `repeatFrequency` is set, so the movement can name it.
    public var recurringRuleID: UUID
    /// Labels besides the category; normalized when saved.
    public var tags: [String]
    /// The business it was with. `keep` leaves an edited movement's as it was (a caller that doesn't
    /// know merchants never unlinks one); `unlinked` removes it, and no categorization rule sets one
    /// then; `new` creates it with the movement. A new movement without a category that no rule
    /// matches takes the merchant's default category. A transfer never names one.
    public var merchant: MerchantLink
    /// The platform it went through, like `merchant`. Never the business itself.
    public var via: MerchantLink

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
        debitedFor: DebitedFor? = nil,
        note: String = "",
        isDraft: Bool = false,
        repeatFrequency: RecurringFrequency? = nil,
        recurringRuleID: UUID = UUID(),
        tags: [String] = [],
        merchant: MerchantLink = .keep,
        via: MerchantLink = .keep,
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
        self.debitedFor = debitedFor
        self.note = note
        self.isDraft = isDraft
        self.repeatFrequency = repeatFrequency
        self.recurringRuleID = recurringRuleID
        self.tags = tags
        self.merchant = merchant
        self.via = via
    }
}

extension TransactionDraft {
    /// The amount, currency and account a bank charge in the principal currency was recorded for.
    public struct DebitedFor: Equatable, Sendable {
        public let amount: Decimal
        public let currency: String
        public let accountID: UUID

        public init(amount: Decimal, currency: String, accountID: UUID) {
            self.amount = amount
            self.currency = currency
            self.accountID = accountID
        }
    }

    /// The charge in the principal currency the draft saves: none when it is in the principal
    /// currency, and none when it was carried over from a saved movement (`debitedFor`) whose amount,
    /// currency or account changed since, since the bank charged it for something else and balances
    /// would follow it.
    public func applicableDebit(principal: String, accountID: UUID?) -> Decimal? {
        guard let actualDebitedPrincipal, currency != principal else { return nil }
        if let debitedFor,
           debitedFor.amount != amount || debitedFor.currency != currency || debitedFor.accountID != accountID
        {
            return nil
        }
        return actualDebitedPrincipal
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
    /// Every tag used, most used first: the tag field's suggestions.
    public let tagUsage: [String]
    /// The person's categorization rules in order, only those whose category still exists.
    public let rules: [CategorizationRule]
    /// The person's merchants; `nil` when they weren't loaded (a movement's links are then taken as
    /// they come).
    public let merchants: [Merchant]?

    public init(
        currencies: CurrencySettings,
        categories: [TransactionCategory],
        accounts: [Account],
        cards: [Card],
        balances: [UUID: [Money]],
        lastUsed: [PaymentSource: Date],
        categoryUsage: [String: Int],
        tagUsage: [String] = [],
        rules: [CategorizationRule] = [],
        merchants: [Merchant]? = nil,
    ) {
        self.currencies = currencies
        self.categories = categories
        self.accounts = accounts
        self.cards = cards
        self.balances = balances
        self.lastUsed = lastUsed
        self.categoryUsage = categoryUsage
        self.tagUsage = tagUsage
        self.rules = rules.filter { rule in categories.contains { $0.id == rule.categoryID && $0.kind == rule.kind } }
        self.merchants = merchants
    }

    public func merchant(_ id: UUID?) -> Merchant? {
        merchants?.first { $0.id == id }
    }

    /// The same context with merchants the person just created, so the flow can show them without
    /// reloading.
    public func adding(merchants added: [Merchant]) -> Self {
        let ids = Set(added.map(\.id))
        return Self(
            currencies: currencies,
            categories: categories,
            accounts: accounts,
            cards: cards,
            balances: balances,
            lastUsed: lastUsed,
            categoryUsage: categoryUsage,
            tagUsage: tagUsage,
            rules: rules,
            merchants: (merchants ?? []).filter { !ids.contains($0.id) } + added,
        )
    }

    public func account(_ id: UUID?) -> Account? {
        accounts.first { $0.id == id }
    }

    /// The context the flow's pickers read: open accounts and their methods, plus the closed ones in
    /// `kept` (the accounts of the movement being edited, which still show, marked closed).
    public func forPickers(keeping kept: [UUID?] = []) -> Self {
        let shown = accounts.filter { $0.isOpen || kept.contains($0.id) }
        guard shown.count != accounts.count else { return self }
        let ids = Set(shown.map(\.id))
        return Self(
            currencies: currencies,
            categories: categories,
            accounts: shown,
            cards: cards.filter { ids.contains($0.accountID) },
            balances: balances,
            lastUsed: lastUsed,
            categoryUsage: categoryUsage,
            tagUsage: tagUsage,
            rules: rules,
            merchants: merchants,
        )
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
            tagUsage: tagUsage,
            rules: rules,
            merchants: merchants,
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
