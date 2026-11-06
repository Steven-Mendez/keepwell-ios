import Foundation

// Categorization rules ("if it says Uber → Transport"). Settings manages them, and the
// create-movement flow and CSV import apply them, so they live in the kernel.

/// What the rule editor hands over. `id` is `nil` for a new rule.
public struct CategorizationRuleDraft: Hashable, Sendable {
    public var id: UUID?
    public var match: String
    public var categoryID: String
    public var kind: TransactionKind
    public var tags: [String]

    public init(id: UUID? = nil, match: String, categoryID: String, kind: TransactionKind, tags: [String] = []) {
        self.id = id
        self.match = match
        self.categoryID = categoryID
        self.kind = kind
        self.tags = tags
    }
}

/// Listing, saving, deleting, ordering and "Apply to past movements".
public protocol ManageCategorizationRulesUseCase: Sendable {
    /// In the person's order: the first that matches wins.
    func rules() async throws(DomainError) -> [CategorizationRule]
    @discardableResult
    func save(_ draft: CategorizationRuleDraft) async throws(DomainError) -> CategorizationRule
    func delete(id: UUID) async throws(DomainError)
    func reorder(ids: [UUID]) async throws(DomainError)
    /// How many existing movements "Apply to past movements" would change, for its confirmation.
    func pastMatchCount(of rule: CategorizationRule) async throws(DomainError) -> Int
    /// Puts the uncategorized (or "Other") movements the rule matches in its category, with its
    /// tags added. Returns how many changed.
    @discardableResult
    func applyToPast(_ rule: CategorizationRule) async throws(DomainError) -> Int
}

public struct DefaultManageCategorizationRulesUseCase: ManageCategorizationRulesUseCase {
    private let repository: any CategorizationRuleRepository
    private let categories: any CategoryRepository
    private let transactions: any TransactionRepository
    private let makeID: @Sendable () -> UUID

    public init(
        rules: any CategorizationRuleRepository,
        categories: any CategoryRepository,
        transactions: any TransactionRepository,
        makeID: @escaping @Sendable () -> UUID = { UUID() },
    ) {
        repository = rules
        self.categories = categories
        self.transactions = transactions
        self.makeID = makeID
    }

    public func rules() async throws(DomainError) -> [CategorizationRule] {
        try await repository.fetchCategorizationRules()
    }

    public func save(_ draft: CategorizationRuleDraft) async throws(DomainError) -> CategorizationRule {
        if let id = draft.id, try await !repository.fetchCategorizationRules().contains(where: { $0.id == id }) {
            throw .notFound(id)
        }
        let known = try await categories.fetchCategories()
        let rule = try CategorizationRule(
            id: draft.id ?? makeID(),
            match: draft.match,
            categoryID: draft.categoryID,
            kind: draft.kind,
            tags: draft.tags,
        ).validated(categories: known)
        try await repository.save(rule)
        return rule
    }

    public func delete(id: UUID) async throws(DomainError) {
        try await repository.deleteCategorizationRule(id: id)
    }

    public func reorder(ids: [UUID]) async throws(DomainError) {
        try await repository.reorderCategorizationRules(ids: ids)
    }

    public func pastMatchCount(of rule: CategorizationRule) async throws(DomainError) -> Int {
        try await CategorizationRules.pastMatches(of: rule, in: transactions.fetchTransactions(in: nil)).count
    }

    public func applyToPast(_ rule: CategorizationRule) async throws(DomainError) -> Int {
        let matches = try await CategorizationRules.pastMatches(of: rule, in: transactions.fetchTransactions(in: nil))
        for transaction in matches {
            try await transactions.save(CategorizationRules.applying(rule, to: transaction))
        }
        return matches.count
    }
}
