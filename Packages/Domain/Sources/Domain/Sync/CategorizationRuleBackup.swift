import Foundation

/// A categorization rule in the backup file (schema 4). `sortIndex` keeps the person's order, which
/// decides which rule wins, the way categories keep theirs.
public struct CategorizationRuleBackup: Codable, Sendable, Equatable {
    public let id: String
    public let match: String
    public let categoryId: String
    public let kind: TransactionKind
    /// Left out when the rule adds none.
    public let tags: [String]?
    public let sortIndex: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?

    init(_ stamped: Stamped<CategorizationRule>, sortIndex: Int) {
        let rule = stamped.value
        id = PortableID.string(rule.id)
        match = rule.match
        categoryId = rule.categoryID
        kind = rule.kind
        tags = rule.tags.isEmpty ? nil : rule.tags
        self.sortIndex = sortIndex
        createdAt = stamped.metadata.createdAt
        updatedAt = stamped.metadata.updatedAt
        deletedAt = stamped.metadata.deletedAt
    }

    /// The text and kind only: its category may be a tombstone in the same file, so the movement
    /// editor skips a rule whose category is gone instead of the restore failing.
    func toDomain() throws(DomainError) -> Stamped<CategorizationRule> {
        guard kind != .transfer else { throw .unsupportedTransactionKind(.transfer) }
        guard !match.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .missingName }
        let rule = try CategorizationRule(id: PortableID.uuid(id), match: match, categoryID: categoryId, kind: kind, tags: tags ?? [])
        return Stamped(rule, RecordMetadata(createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt))
    }
}
