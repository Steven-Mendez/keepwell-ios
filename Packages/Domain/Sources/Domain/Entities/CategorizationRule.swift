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
    /// The business the movement was with, set when it names none yet.
    public let merchantID: UUID?

    public init(
        id: UUID = UUID(),
        match: String,
        categoryID: String,
        kind: TransactionKind,
        tags: [String] = [],
        merchantID: UUID? = nil,
    ) {
        self.id = id
        self.match = match
        self.categoryID = categoryID
        self.kind = kind
        self.tags = Tags.normalized(tags)
        self.merchantID = merchantID
    }

    /// The same rule naming another merchant, or none.
    public func with(merchantID: UUID?) -> Self {
        Self(id: id, match: match, categoryID: categoryID, kind: kind, tags: tags, merchantID: merchantID)
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
        return Self(id: id, match: text, categoryID: categoryID, kind: kind, tags: tags, merchantID: merchantID)
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

    /// The rule that categorizes a new movement with these fields: none unless it is uncategorized
    /// (no category, or "Other" of its kind), otherwise the first that matches.
    public static func categorizing(
        kind: TransactionKind,
        categoryID: String?,
        description: String,
        note: String?,
        in rules: [CategorizationRule],
    ) -> CategorizationRule? {
        guard kind != .transfer, categoryID == nil || categoryID == TransactionCategory.otherID(for: kind) else { return nil }
        return firstMatch(in: rules, kind: kind, description: description, note: note)
    }

    /// A new uncategorized movement takes the first rule that matches; otherwise it stays as it is.
    /// Saving a new movement and recording a recurring occurrence go through it; edits never do.
    /// `merchants` are the live ones a rule's merchant may link (`applying`).
    public static func autoCategorized(
        _ transaction: Transaction,
        rules: [CategorizationRule],
        merchants: [Merchant] = [],
    ) -> Transaction {
        let rule = categorizing(
            kind: transaction.kind,
            categoryID: transaction.categoryID,
            description: transaction.description,
            note: transaction.note,
            in: rules,
        )
        return rule.map { applying($0, to: transaction, merchants: merchants) } ?? transaction
    }

    /// The rules saving may apply: those whose category still exists with the rule's kind, in order.
    public static func usable(_ rules: [CategorizationRule], categories: [TransactionCategory]) -> [CategorizationRule] {
        rules.filter { rule in categories.contains { $0.id == rule.categoryID && $0.kind == rule.kind } }
    }

    /// The movement in the rule's category, with the rule's tags after its own and the rule's
    /// merchant when it names none yet (one the person picked stays). The rule's merchant is set only
    /// when it is one of `merchants` (the live ones: a rule may still name one deleted elsewhere until
    /// the repair after a pull) and `mayLinkMerchant` (`false` when the person cleared the business on
    /// purpose: a cleared business is never overridden by a rule).
    public static func applying(
        _ rule: CategorizationRule,
        to transaction: Transaction,
        merchants: [Merchant] = [],
        mayLinkMerchant: Bool = true,
    ) -> Transaction {
        let categorized = transaction.with(categoryID: rule.categoryID, tags: Tags.merging(transaction.tags, with: rule.tags))
        guard mayLinkMerchant, let merchantID = rule.merchantID, transaction.merchantID == nil,
              merchants.contains(where: { $0.id == merchantID })
        else { return categorized }
        // The platform is never the business itself (`Transaction.init` drops it).
        return categorized.with(merchantID: merchantID, viaMerchantID: transaction.viaMerchantID)
    }
}
