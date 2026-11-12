import Domain
import Foundation
import SwiftData

/// A categorization rule. Every property is optional or defaulted and nothing is unique, as CloudKit
/// requires; `sortIndex` keeps the person's order, which decides the rule that wins.
@Model
public final class CategorizationRuleRecord: AuditedRecord {
    public var id = UUID()
    var match = ""
    var categoryID = ""
    var kindRaw = TransactionKind.expense.rawValue
    /// One tag per line, like a movement's.
    var tagsText = ""
    var sortIndex = 0
    var createdAt = Date.now
    var updatedAt = Date.now
    var deletedAt: Date?

    init(id: UUID) {
        self.id = id
    }

    func update(from rule: CategorizationRule, sortIndex: Int) {
        match = rule.match
        categoryID = rule.categoryID
        kindRaw = rule.kind.rawValue
        tagsText = TagsText.encode(rule.tags)
        self.sortIndex = sortIndex
    }

    func toDomain() throws(DomainCorruption) -> CategorizationRule {
        guard let kind = TransactionKind(rawValue: kindRaw) else {
            throw DomainCorruption("Categorization rule kind '\(kindRaw)'")
        }
        return CategorizationRule(id: id, match: match, categoryID: categoryID, kind: kind, tags: TagsText.decode(tagsText))
    }
}

extension CategorizationRuleRecord {
    /// The person's order. Two offline devices can give rules the same `sortIndex`, so the id breaks
    /// the tie: the same order the web and the API use, hence the same winning rule everywhere.
    /// Uppercase hex sorts like the lowercase id on the wire.
    static func inPlace(_ lhs: CategorizationRuleRecord, _ rhs: CategorizationRuleRecord) -> Bool {
        (lhs.sortIndex, lhs.id.uuidString) < (rhs.sortIndex, rhs.id.uuidString)
    }
}
