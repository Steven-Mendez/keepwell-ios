import Foundation

/// A recurring rule in the backup file (schema 2), with the same key style as `TransactionBackup`.
public struct RecurringRuleBackup: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let kind: TransactionKind
    public let categoryId: String?
    /// Always positive; `kind` carries the direction.
    public let amount: String
    public let currency: String
    public let accountId: String
    public let cardId: String?
    public let destinationAccountId: String?
    public let frequency: RecurringFrequency
    public let interval: Int
    public let startDate: Date
    public let nextDate: Date
    public let endDate: Date?
    public let isSubscription: Bool
    public let autoConfirm: Bool
    public let isPaused: Bool
    public let note: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?

    init(_ stamped: Stamped<RecurringRule>) {
        let rule = stamped.value
        id = PortableID.string(rule.id)
        name = rule.name
        kind = rule.kind
        categoryId = rule.categoryID
        amount = PortableDecimal.string(rule.amount)
        currency = rule.currency
        accountId = PortableID.string(rule.accountID)
        cardId = rule.cardID.map(PortableID.string)
        destinationAccountId = rule.destinationAccountID.map(PortableID.string)
        frequency = rule.frequency
        interval = rule.interval
        startDate = rule.startDate
        nextDate = rule.nextDate
        endDate = rule.endDate
        isSubscription = rule.isSubscription
        autoConfirm = rule.autoConfirm
        isPaused = rule.isPaused
        note = rule.note
        createdAt = stamped.metadata.createdAt
        updatedAt = stamped.metadata.updatedAt
        deletedAt = stamped.metadata.deletedAt
    }

    func toDomain() throws(DomainError) -> Stamped<RecurringRule> {
        let rule = try RecurringRule(
            id: PortableID.uuid(id),
            name: name,
            kind: kind,
            categoryID: categoryId,
            amount: PortableDecimal.decimal(amount),
            currency: Money.normalizedCurrency(currency),
            accountID: PortableID.uuid(accountId),
            cardID: cardId.map { id throws(DomainError) in try PortableID.uuid(id) },
            destinationAccountID: destinationAccountId.map { id throws(DomainError) in try PortableID.uuid(id) },
            frequency: frequency,
            interval: interval,
            startDate: startDate,
            nextDate: nextDate,
            endDate: endDate,
            isSubscription: isSubscription,
            autoConfirm: autoConfirm,
            isPaused: isPaused,
            note: note,
        )
        // The amount and interval only: what it pays with may be a tombstone in the same file, and
        // the end date was checked by calendar day in a time zone this file doesn't record.
        try Transaction.checkAmounts(rule.amount)
        guard RecurringRule.intervalRange.contains(interval) else { throw .invalidInterval(interval) }
        return Stamped(rule, RecordMetadata(createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt))
    }
}
