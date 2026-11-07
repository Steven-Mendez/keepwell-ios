import Foundation

/// A movement. `amount` is always positive; `kind` carries the direction, so a mis-signed value
/// can't silently flip an expense into income.
public struct Transaction: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let date: Date
    /// `planned` movements don't count toward balances or summaries until confirmed (rule 1).
    public let status: TransactionStatus
    public let description: String
    public let kind: TransactionKind
    /// `nil` for transfers, which have no category.
    public let categoryID: String?
    public let amount: Decimal
    public let currency: String
    /// Source account, derived from the payment method when there is one (rule 3).
    public let accountID: UUID
    public let cardID: UUID?
    /// Transfers only.
    public let destinationAccountID: UUID?
    /// What the bank actually charged in the principal currency, when it used its own rate.
    public let actualDebitedPrincipal: Decimal?
    /// The rate in force when this was recorded; conversions always use it.
    public let exchangeRate: ExchangeRate
    /// Others owe part of it.
    public let isShared: Bool
    public let note: String?
    /// The recurring rule that produced it, if any. It may outlive the rule: deleting a rule keeps
    /// the confirmed movements it made.
    public let recurringID: UUID?
    /// Labels besides the category ("viaje-mexico"), normalized by `Tags`, each once, in the order
    /// they were added.
    public let tags: [String]
    /// `mcp` when Claude (or another MCP client) recorded it.
    public let source: RecordSource

    public init(
        id: UUID = UUID(),
        date: Date,
        status: TransactionStatus = .confirmed,
        description: String,
        kind: TransactionKind,
        categoryID: String?,
        amount: Decimal,
        currency: String,
        accountID: UUID,
        cardID: UUID? = nil,
        destinationAccountID: UUID? = nil,
        actualDebitedPrincipal: Decimal? = nil,
        exchangeRate: ExchangeRate,
        isShared: Bool = false,
        note: String? = nil,
        recurringID: UUID? = nil,
        tags: [String] = [],
        source: RecordSource = .app,
    ) {
        self.id = id
        self.date = date
        self.status = status
        self.description = description
        self.kind = kind
        self.categoryID = categoryID
        self.amount = amount
        self.currency = currency
        self.accountID = accountID
        self.cardID = cardID
        self.destinationAccountID = destinationAccountID
        self.actualDebitedPrincipal = actualDebitedPrincipal
        self.exchangeRate = exchangeRate
        self.isShared = isShared
        self.note = note
        self.recurringID = recurringID
        self.tags = Tags.normalized(tags)
        self.source = source
    }

    /// The rule behind "`amount` is always positive", kept here so every path that records a
    /// movement (the create flow, Siri, ATM withdrawals, CSV imports) enforces the same one. A known
    /// bank charge must be positive too, or the principal balance would move the wrong way.
    public static func checkAmounts(_ amount: Decimal, actualDebitedPrincipal: Decimal? = nil) throws(DomainError) {
        guard amount > 0, (actualDebitedPrincipal ?? 1) > 0 else { throw .invalidAmount }
    }

    public var isConfirmed: Bool {
        status == .confirmed
    }

    /// The same movement, now counting toward balances.
    public func confirmed() -> Self {
        with(status: .confirmed)
    }

    public func with(status: TransactionStatus) -> Self {
        Self(
            id: id, date: date, status: status, description: description, kind: kind, categoryID: categoryID,
            amount: amount, currency: currency, accountID: accountID, cardID: cardID,
            destinationAccountID: destinationAccountID, actualDebitedPrincipal: actualDebitedPrincipal,
            exchangeRate: exchangeRate, isShared: isShared, note: note, recurringID: recurringID, tags: tags,
            source: source,
        )
    }

    /// The same movement in another category and with other tags (a categorization rule applied).
    public func with(categoryID: String?, tags: [String]) -> Self {
        Self(
            id: id, date: date, status: status, description: description, kind: kind, categoryID: categoryID,
            amount: amount, currency: currency, accountID: accountID, cardID: cardID,
            destinationAccountID: destinationAccountID, actualDebitedPrincipal: actualDebitedPrincipal,
            exchangeRate: exchangeRate, isShared: isShared, note: note, recurringID: recurringID, tags: tags,
            source: source,
        )
    }
}

extension Transaction {
    /// Movements written before tags existed (the version 1 backup document) have no `tags`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            date: container.decode(Date.self, forKey: .date),
            status: container.decode(TransactionStatus.self, forKey: .status),
            description: container.decode(String.self, forKey: .description),
            kind: container.decode(TransactionKind.self, forKey: .kind),
            categoryID: container.decodeIfPresent(String.self, forKey: .categoryID),
            amount: container.decode(Decimal.self, forKey: .amount),
            currency: container.decode(String.self, forKey: .currency),
            accountID: container.decode(UUID.self, forKey: .accountID),
            cardID: container.decodeIfPresent(UUID.self, forKey: .cardID),
            destinationAccountID: container.decodeIfPresent(UUID.self, forKey: .destinationAccountID),
            actualDebitedPrincipal: container.decodeIfPresent(Decimal.self, forKey: .actualDebitedPrincipal),
            exchangeRate: container.decode(ExchangeRate.self, forKey: .exchangeRate),
            isShared: container.decode(Bool.self, forKey: .isShared),
            note: container.decodeIfPresent(String.self, forKey: .note),
            recurringID: container.decodeIfPresent(UUID.self, forKey: .recurringID),
            tags: container.decodeIfPresent([String].self, forKey: .tags) ?? [],
            source: container.decodeIfPresent(RecordSource.self, forKey: .source) ?? .app,
        )
    }
}
