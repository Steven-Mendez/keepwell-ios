import Foundation

/// How often a recurring rule repeats; `RecurringRule.interval` says every how many.
public enum RecurringFrequency: String, Codable, CaseIterable, Sendable {
    /// Every 7 days.
    case weekly
    case monthly
    case yearly
}

/// A template that records a movement on a schedule: rent every month, a streaming service every
/// year, a salary every two weeks. Each occurrence becomes a `Transaction` carrying the rule's id.
///
/// The schedule always counts from `startDate`, never from the previous (possibly clamped)
/// occurrence, so "the 31st" stays the 31st in the months that have one. See `RecurringSchedule`.
public struct RecurringRule: Identifiable, Hashable, Sendable, Codable {
    /// "Every 1 to 99" weeks, months or years.
    public static let intervalRange = 1 ... 99

    public let id: UUID
    /// Becomes each movement's description.
    public let name: String
    public let kind: TransactionKind
    /// `nil` for transfers, as on a movement.
    public let categoryID: String?
    /// Always positive; `kind` carries the direction.
    public let amount: Decimal
    public let currency: String
    /// Source account, derived from the card when there is one (same rule as a movement).
    public let accountID: UUID
    public let cardID: UUID?
    /// Transfers only.
    public let destinationAccountID: UUID?
    public let frequency: RecurringFrequency
    public let interval: Int
    /// The first occurrence and the anchor of every later one; its time of day is kept on each.
    public let startDate: Date
    /// The next occurrence not yet recorded as a movement.
    public let nextDate: Date
    /// The last day an occurrence may fall on (inclusive, by calendar day).
    public let endDate: Date?
    /// Listed under "Subscriptions" and reminded the day before it renews.
    public let isSubscription: Bool
    /// `true` saves occurrences confirmed; `false` saves them as drafts waiting for confirmation.
    public let autoConfirm: Bool
    /// A paused rule records nothing and keeps `nextDate` where it was.
    public let isPaused: Bool
    /// Copied to each movement's note.
    public let note: String?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: TransactionKind,
        categoryID: String?,
        amount: Decimal,
        currency: String,
        accountID: UUID,
        cardID: UUID? = nil,
        destinationAccountID: UUID? = nil,
        frequency: RecurringFrequency,
        interval: Int = 1,
        startDate: Date,
        nextDate: Date? = nil,
        endDate: Date? = nil,
        isSubscription: Bool = false,
        autoConfirm: Bool = false,
        isPaused: Bool = false,
        note: String? = nil,
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.categoryID = categoryID
        self.amount = amount
        self.currency = currency
        self.accountID = accountID
        self.cardID = cardID
        self.destinationAccountID = destinationAccountID
        self.frequency = frequency
        self.interval = interval
        self.startDate = startDate
        self.nextDate = nextDate ?? startDate
        self.endDate = endDate
        self.isSubscription = isSubscription
        self.autoConfirm = autoConfirm
        self.isPaused = isPaused
        self.note = note
    }

    /// The rule's own limits: a positive amount, a name, an interval of 1–99 and an end that isn't
    /// before the start. What it pays with is checked against the ledger by `validated(…)`.
    public func checkSchedule(calendar: Calendar) throws(DomainError) {
        try Transaction.checkAmounts(amount)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .missingName }
        guard Self.intervalRange.contains(interval) else { throw .invalidInterval(interval) }
        if let endDate, calendar.startOfDay(for: endDate) < calendar.startOfDay(for: startDate) {
            throw .invalidEndDate
        }
    }

    /// The rule checked by the same rules as a movement it would record, normalized the same way:
    /// the account comes from the card, transfers drop the category, others drop the destination,
    /// and the name and note are trimmed.
    public func validated(
        currencies: CurrencySettings,
        accounts: [Account],
        cards: [Card],
        categories: [TransactionCategory],
        calendar: Calendar,
    ) throws(DomainError) -> Self {
        try checkSchedule(calendar: calendar)
        try Transaction.checkCurrency(currency, currencies: currencies)
        var source = accountID
        if let cardID {
            guard let card = cards.first(where: { $0.id == cardID }) else { throw .notFound(cardID) }
            source = card.accountID
        }
        guard accounts.contains(where: { $0.id == source }) else { throw .notFound(source) }
        if kind == .transfer {
            try Transaction.checkDestination(destinationAccountID, from: source, accounts: accounts)
        } else {
            try Transaction.checkCategory(categoryID, kind: kind, categories: categories)
        }
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            categoryID: kind == .transfer ? nil : categoryID,
            accountID: source,
            destinationAccountID: kind == .transfer ? destinationAccountID : nil,
            note: trimmedNote?.isEmpty == false ? trimmedNote : nil,
        )
    }

    /// The same rule with its next occurrence moved.
    public func with(nextDate: Date) -> Self {
        Self(
            id: id, name: name, kind: kind, categoryID: categoryID, amount: amount, currency: currency,
            accountID: accountID, cardID: cardID, destinationAccountID: destinationAccountID, frequency: frequency,
            interval: interval, startDate: startDate, nextDate: nextDate, endDate: endDate,
            isSubscription: isSubscription, autoConfirm: autoConfirm, isPaused: isPaused, note: note,
        )
    }

    public func with(isPaused: Bool, nextDate: Date) -> Self {
        Self(
            id: id, name: name, kind: kind, categoryID: categoryID, amount: amount, currency: currency,
            accountID: accountID, cardID: cardID, destinationAccountID: destinationAccountID, frequency: frequency,
            interval: interval, startDate: startDate, nextDate: nextDate, endDate: endDate,
            isSubscription: isSubscription, autoConfirm: autoConfirm, isPaused: isPaused, note: note,
        )
    }

    /// The same rule paid with another method of the same account.
    public func with(cardID: UUID?) -> Self {
        Self(
            id: id, name: name, kind: kind, categoryID: categoryID, amount: amount, currency: currency,
            accountID: accountID, cardID: cardID, destinationAccountID: destinationAccountID, frequency: frequency,
            interval: interval, startDate: startDate, nextDate: nextDate, endDate: endDate,
            isSubscription: isSubscription, autoConfirm: autoConfirm, isPaused: isPaused, note: note,
        )
    }

    private func copy(name: String, categoryID: String?, accountID: UUID, destinationAccountID: UUID?, note: String?) -> Self {
        Self(
            id: id, name: name, kind: kind, categoryID: categoryID, amount: amount, currency: currency,
            accountID: accountID, cardID: cardID, destinationAccountID: destinationAccountID, frequency: frequency,
            interval: interval, startDate: startDate, nextDate: nextDate, endDate: endDate,
            isSubscription: isSubscription, autoConfirm: autoConfirm, isPaused: isPaused, note: note,
        )
    }
}
