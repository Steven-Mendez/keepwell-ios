import Foundation

/// When a stored record was created, last changed and soft-deleted. The store stamps it on every
/// write, so entities stay free of it; backups and a future sync engine read it to merge copies
/// of the same record from different devices (last `updatedAt` wins, a `deletedAt` is a tombstone).
public struct RecordMetadata: Hashable, Sendable {
    public let createdAt: Date
    public let updatedAt: Date
    /// `nil` while the record is alive. Deleted records stay stored so the deletion can reach
    /// other devices instead of the record coming back from one that still has it.
    public let deletedAt: Date?

    public init(createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public var isDeleted: Bool {
        deletedAt != nil
    }
}

/// A domain value with the metadata of the record that stores it.
public struct Stamped<Value: Hashable & Sendable>: Hashable, Sendable {
    public let value: Value
    public let metadata: RecordMetadata

    public init(_ value: Value, _ metadata: RecordMetadata) {
        self.value = value
        self.metadata = metadata
    }
}

/// Everything the store holds, deleted records included, as domain values. What a backup writes
/// and a restore replaces the store with.
public struct BackupContents: Hashable, Sendable {
    /// `nil` before onboarding saves the first settings.
    public var settings: Stamped<Settings>?
    public var accounts: [Stamped<Account>]
    public var cards: [Stamped<Card>]
    /// In the person's order.
    public var categories: [Stamped<TransactionCategory>]
    public var transactions: [Stamped<Transaction>]
    public var recurringRules: [Stamped<RecurringRule>]
    public var savingsGoals: [Stamped<SavingsGoal>]

    public init(
        settings: Stamped<Settings>?,
        accounts: [Stamped<Account>],
        cards: [Stamped<Card>],
        categories: [Stamped<TransactionCategory>],
        transactions: [Stamped<Transaction>],
        recurringRules: [Stamped<RecurringRule>] = [],
        savingsGoals: [Stamped<SavingsGoal>] = [],
    ) {
        self.settings = settings
        self.accounts = accounts
        self.cards = cards
        self.categories = categories
        self.transactions = transactions
        self.recurringRules = recurringRules
        self.savingsGoals = savingsGoals
    }
}
