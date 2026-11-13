import Foundation

// Merchants: the business a movement was with ("Subway") and, optionally, the platform it went
// through ("via Uber Eats"). Settings manages them and the movement editor creates them, so they live
// in the kernel. keepwell-web has the same use cases (`src/lib/domain/merchants.ts`).

/// Listing, creating, editing, deleting and merging merchants.
public protocol ManageMerchantsUseCase: Sendable {
    /// By name.
    func merchants() async throws(DomainError) -> [Merchant]
    /// Saves a new merchant or edits one (rename, domain, brand, default category, platform). Every
    /// field but `isPlatform` is replaced as given: one left out is removed.
    @discardableResult
    func save(_ draft: MerchantDraft) async throws(DomainError) -> Merchant
    /// The merchant a picker chose: the existing one it names (`Merchants.equivalent`), or a new one.
    /// Picking "Subway" from the brand table twice gives the same merchant.
    @discardableResult
    func create(_ draft: MerchantDraft) async throws(DomainError) -> Merchant
    /// Deletes a merchant, all or nothing. Movements and rules that named it keep everything else and
    /// simply name no business (or no platform) any more.
    func delete(id: UUID) async throws(DomainError)
    /// Merges `fromID` into `intoID`, all or nothing: whatever named the first (as business or as
    /// platform) names the second, which takes the first's domain, brand and default category where
    /// it has none (a default category only when it still exists, and also over one of the second's
    /// that no longer does), and is a platform if either was. The first is deleted.
    @discardableResult
    func merge(_ fromID: UUID, into intoID: UUID) async throws(DomainError) -> Merchant
    /// How many movements name each merchant, as business or platform.
    func movementCounts() async throws(DomainError) -> [UUID: Int]
}

public struct DefaultManageMerchantsUseCase: ManageMerchantsUseCase {
    private let repository: any MerchantRepository
    private let categories: any CategoryRepository
    private let transactions: any TransactionRepository
    private let recurringRules: any RecurringRuleRepository
    private let categorizationRules: any CategorizationRuleRepository
    private let makeID: @Sendable () -> UUID

    public init(
        merchants: any MerchantRepository,
        categories: any CategoryRepository,
        transactions: any TransactionRepository,
        recurringRules: any RecurringRuleRepository,
        categorizationRules: any CategorizationRuleRepository,
        makeID: @escaping @Sendable () -> UUID = { UUID() },
    ) {
        repository = merchants
        self.categories = categories
        self.transactions = transactions
        self.recurringRules = recurringRules
        self.categorizationRules = categorizationRules
        self.makeID = makeID
    }

    public func merchants() async throws(DomainError) -> [Merchant] {
        try await Merchants.ordered(repository.fetchMerchants())
    }

    private func existing(_ id: UUID) async throws(DomainError) -> Merchant {
        guard let merchant = try await repository.fetchMerchants().first(where: { $0.id == id }) else { throw .notFound(id) }
        return merchant
    }

    public func save(_ draft: MerchantDraft) async throws(DomainError) -> Merchant {
        var current: Merchant?
        if let id = draft.id {
            current = try await existing(id)
        }
        let merchant = try await Merchants.validated(
            draft,
            id: current?.id ?? makeID(),
            categories: categories.fetchCategories(),
            current: current,
        )
        try await repository.save(merchant)
        return merchant
    }

    public func create(_ draft: MerchantDraft) async throws(DomainError) -> Merchant {
        var draft = draft
        draft.id = nil
        if let found = try await Merchants.equivalent(in: repository.fetchMerchants(), to: draft) {
            return found
        }
        return try await save(draft)
    }

    public func delete(id: UUID) async throws(DomainError) {
        _ = try await existing(id)
        var changes = try await relinking(from: id, to: nil)
        changes.deletedMerchantIDs = [id]
        try await repository.commit(changes)
    }

    public func merge(_ fromID: UUID, into intoID: UUID) async throws(DomainError) -> Merchant {
        let from = try await existing(fromID)
        let into = try await existing(intoID)
        guard from.id != into.id else { return into }
        let known = try await categories.fetchCategories()
        // Only a default category that still exists is carried over, and it fills one the target
        // lacks or whose own no longer exists.
        let takesCategory = !Merchants.isLiveDefaultCategory(into.defaultCategoryID, categories: known)
            && Merchants.isLiveDefaultCategory(from.defaultCategoryID, categories: known)
        let merged = Merchant(
            id: into.id,
            name: into.name,
            domain: into.domain ?? from.domain,
            brandID: into.brandID ?? from.brandID,
            defaultCategoryID: takesCategory ? from.defaultCategoryID : into.defaultCategoryID,
            isPlatform: into.isPlatform || from.isPlatform,
        )
        var changes = try await relinking(from: from.id, to: into.id)
        if merged != into {
            changes.savedMerchants = [merged]
        }
        changes.deletedMerchantIDs = [from.id]
        try await repository.commit(changes)
        return merged
    }

    public func movementCounts() async throws(DomainError) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for movement in try await transactions.fetchTransactions(in: nil) {
            for id in Set([movement.merchantID, movement.viaMerchantID].compactMap(\.self)) {
                counts[id, default: 0] += 1
            }
        }
        return counts
    }

    /// Every link to `from` moved to `to` (or removed without one), in movements, recurring rules
    /// and categorization rules.
    private func relinking(from: UUID, to: UUID?) async throws(DomainError) -> MerchantChanges {
        try await MerchantChanges.relinking(
            from: [from],
            to: to,
            transactions: transactions.fetchTransactions(in: nil),
            recurringRules: recurringRules.fetchRecurringRules(),
            categorizationRules: categorizationRules.fetchCategorizationRules(),
        )
    }
}

extension MerchantChanges {
    /// The records that name one of `ids`, with each of those links moved to `to` (or removed).
    static func relinking(
        from ids: Set<UUID>,
        to: UUID?,
        transactions: [Transaction],
        recurringRules: [RecurringRule],
        categorizationRules: [CategorizationRule],
    ) -> MerchantChanges {
        func moved(_ merchantID: UUID?, _ viaMerchantID: UUID?) -> (merchantID: UUID?, viaMerchantID: UUID?)? {
            var links: (merchantID: UUID?, viaMerchantID: UUID?)?
            for id in ids {
                let current = links ?? (merchantID, viaMerchantID)
                if let next = Merchants.relinked(merchantID: current.merchantID, viaMerchantID: current.viaMerchantID, from: id, to: to) {
                    links = next
                }
            }
            return links
        }
        return MerchantChanges(
            transactions: transactions.compactMap { movement in
                moved(movement.merchantID, movement.viaMerchantID)
                    .map { movement.with(merchantID: $0.merchantID, viaMerchantID: $0.viaMerchantID) }
            },
            recurringRules: recurringRules.compactMap { rule in
                moved(rule.merchantID, rule.viaMerchantID).map { rule.with(merchantID: $0.merchantID, viaMerchantID: $0.viaMerchantID) }
            },
            categorizationRules: categorizationRules.compactMap { rule in
                guard let id = rule.merchantID, ids.contains(id) else { return nil }
                return rule.with(merchantID: to)
            },
        )
    }
}

/// Runs after every pull, like `ReassignDeletedCategoriesUseCase`: a device that linked a movement
/// (or rule) to a merchant before it heard of the merchant's deletion brings the deleted id back.
/// Whatever still names one of `deletedMerchantIDs` (the tombstones) names no merchant now, as
/// deleting it did; with nothing to repair nothing is written. Returns how many records changed.
public protocol UnlinkDeletedMerchantsUseCase: Sendable {
    @discardableResult
    func execute(deletedMerchantIDs: Set<UUID>) async throws(DomainError) -> Int
}

public struct DefaultUnlinkDeletedMerchantsUseCase: UnlinkDeletedMerchantsUseCase {
    private let merchants: any MerchantRepository
    private let transactions: any TransactionRepository
    private let recurringRules: any RecurringRuleRepository
    private let categorizationRules: any CategorizationRuleRepository

    public init(
        merchants: any MerchantRepository,
        transactions: any TransactionRepository,
        recurringRules: any RecurringRuleRepository,
        categorizationRules: any CategorizationRuleRepository,
    ) {
        self.merchants = merchants
        self.transactions = transactions
        self.recurringRules = recurringRules
        self.categorizationRules = categorizationRules
    }

    @discardableResult
    public func execute(deletedMerchantIDs: Set<UUID>) async throws(DomainError) -> Int {
        guard !deletedMerchantIDs.isEmpty else { return 0 }
        let changes = try await MerchantChanges.relinking(
            from: deletedMerchantIDs,
            to: nil,
            transactions: transactions.fetchTransactions(in: nil),
            recurringRules: recurringRules.fetchRecurringRules(),
            categorizationRules: categorizationRules.fetchCategorizationRules(),
        )
        guard !changes.isEmpty else { return 0 }
        try await merchants.commit(changes)
        return changes.transactions.count + changes.recurringRules.count + changes.categorizationRules.count
    }
}
