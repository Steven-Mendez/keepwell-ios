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
    /// The business the rule sets on the movements it matches; `nil` for none.
    public var merchantID: UUID?

    public init(
        id: UUID? = nil,
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
        self.tags = tags
        self.merchantID = merchantID
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
    /// Every tag used on movements, most used first, for the rule editor's suggestions.
    func tagUsage() async throws(DomainError) -> [String]
    /// The merchants a rule can name, by name. Empty when merchants aren't available.
    func merchants() async throws(DomainError) -> [Merchant]
}

public struct DefaultManageCategorizationRulesUseCase: ManageCategorizationRulesUseCase {
    private let repository: any CategorizationRuleRepository
    private let categories: any CategoryRepository
    private let transactions: any TransactionRepository
    private let merchants: (any MerchantRepository)?
    private let makeID: @Sendable () -> UUID

    /// Without `merchants`, a rule's merchant can't be checked, so a draft naming one is refused.
    public init(
        rules: any CategorizationRuleRepository,
        categories: any CategoryRepository,
        transactions: any TransactionRepository,
        merchants: (any MerchantRepository)? = nil,
        makeID: @escaping @Sendable () -> UUID = { UUID() },
    ) {
        repository = rules
        self.categories = categories
        self.transactions = transactions
        self.merchants = merchants
        self.makeID = makeID
    }

    public func rules() async throws(DomainError) -> [CategorizationRule] {
        try await repository.fetchCategorizationRules()
    }

    public func save(_ draft: CategorizationRuleDraft) async throws(DomainError) -> CategorizationRule {
        var existing: CategorizationRule?
        if let id = draft.id {
            existing = try await repository.fetchCategorizationRules().first { $0.id == id }
            if existing == nil {
                throw .notFound(id)
            }
        }
        let known = try await categories.fetchCategories()
        let rule = try CategorizationRule(
            id: draft.id ?? makeID(),
            match: draft.match,
            categoryID: draft.categoryID,
            kind: draft.kind,
            tags: draft.tags,
            merchantID: draft.merchantID,
        ).validated(categories: known)
        // The merchant the rule already had stays even when it isn't here (yet): it may have been
        // set elsewhere, and editing the rest of the rule must not clear it. A newly chosen one
        // has to be a live merchant.
        if let merchantID = rule.merchantID, merchantID != existing?.merchantID,
           try await merchants?.fetchMerchants().contains(where: { $0.id == merchantID }) != true
        {
            throw .notFound(merchantID)
        }
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
        // One save, so a failure leaves every movement as it was.
        let live = try await merchants?.fetchMerchants() ?? []
        try await transactions.save(matches.map { CategorizationRules.applying(rule, to: $0, merchants: live) })
        return matches.count
    }

    public func tagUsage() async throws(DomainError) -> [String] {
        try await Tags.usage(in: transactions.fetchTransactions(in: nil))
    }

    public func merchants() async throws(DomainError) -> [Merchant] {
        try await Merchants.ordered(merchants?.fetchMerchants() ?? [])
    }
}
