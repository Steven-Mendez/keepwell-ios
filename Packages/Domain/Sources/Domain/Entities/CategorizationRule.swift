import Foundation

/// "If it says Uber → Transport": a new movement whose description or note contains `match` gets
/// `categoryID` (and `tags`) when the person hasn't picked a category. Rules are ordered and the
/// first that matches wins. The web app ports it one to one (`src/lib/domain/categorization.ts`).
public struct CategorizationRule: Identifiable, Hashable, Sendable, Codable {
    /// Room for a merchant's name or a phrase ("PAYPAL *SPOTIFY"), short enough for a list row.
    public static let maxMatchLength = 60

    public let id: UUID
    /// Compared without case or accents, anywhere in the description or note.
    public let match: String
    public let categoryID: String
    /// Expense or income: a rule only applies to movements of its kind, like its category.
    public let kind: TransactionKind
    /// Added to the movement, normalized like any tag.
    public let tags: [String]

    public init(id: UUID = UUID(), match: String, categoryID: String, kind: TransactionKind, tags: [String] = []) {
        self.id = id
        self.match = match
        self.categoryID = categoryID
        self.kind = kind
        self.tags = Tags.normalized(tags)
    }

    /// Whether a movement of this kind with this description and note falls under the rule.
    public func matches(kind: TransactionKind, description: String, note: String?) -> Bool {
        let needle = CategorizationRules.folded(match.trimmingCharacters(in: .whitespacesAndNewlines))
        guard kind == self.kind, !needle.isEmpty else { return false }
        return [description, note ?? ""].contains { CategorizationRules.folded($0).contains(needle) }
    }

    /// The rule as saving stores it: the text trimmed and cut to the limit, expense or income
    /// only, and a category of that kind that exists.
    public func validated(categories: [TransactionCategory]) throws(DomainError) -> Self {
        let text = String(match.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxMatchLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw .missingName }
        guard kind != .transfer else { throw .unsupportedTransactionKind(.transfer) }
        try Transaction.checkCategory(categoryID, kind: kind, categories: categories)
        return Self(id: id, match: text, categoryID: categoryID, kind: kind, tags: tags)
    }
}

public enum CategorizationRules {
    /// The comparison key "Café" and "CAFE" share, as searches use.
    public static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The first rule, in the person's order, that a movement with this text falls under.
    public static func firstMatch(
        in rules: [CategorizationRule],
        kind: TransactionKind,
        description: String,
        note: String?,
    ) -> CategorizationRule? {
        rules.first { $0.matches(kind: kind, description: description, note: note) }
    }

    /// Whether a movement counts as not categorized yet: no category, or the catch-all "Other" of
    /// its kind. Only those are filled by a rule after the fact (imports, "Apply to past movements").
    public static func isUncategorized(_ transaction: Transaction) -> Bool {
        guard transaction.kind != .transfer else { return false }
        return transaction.categoryID == nil || transaction.categoryID == TransactionCategory.otherID(for: transaction.kind)
    }

    /// The movements "Apply to past movements" changes: uncategorized ones the rule matches, and not
    /// already in its category.
    public static func pastMatches(of rule: CategorizationRule, in transactions: [Transaction]) -> [Transaction] {
        transactions.filter { transaction in
            isUncategorized(transaction) && transaction.categoryID != rule.categoryID
                && rule.matches(kind: transaction.kind, description: transaction.description, note: transaction.note)
        }
    }

    /// The movement in the rule's category, with the rule's tags after its own.
    public static func applying(_ rule: CategorizationRule, to transaction: Transaction) -> Transaction {
        transaction.with(categoryID: rule.categoryID, tags: Tags.merging(transaction.tags, with: rule.tags))
    }
}
