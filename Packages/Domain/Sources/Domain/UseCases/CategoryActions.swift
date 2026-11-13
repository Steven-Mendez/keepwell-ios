import Foundation

// Creating and managing categories, the shipped defaults included. Both the create-movement flow
// and settings use them, so they live in the kernel.

/// What the category editor hands over. `id` is `nil` for a new category.
public struct CategoryDraft: Hashable, Sendable {
    public var id: String?
    public var name: String
    public var kind: TransactionKind
    public var icon: String?
    public var color: String?
    /// `nil` for no budget. Dropped for anything but an expense category.
    public var monthlyBudget: Money?

    public init(
        id: String? = nil,
        name: String,
        kind: TransactionKind,
        icon: String? = nil,
        color: String? = nil,
        monthlyBudget: Money? = nil,
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.icon = icon
        self.color = color
        self.monthlyBudget = monthlyBudget
    }

    /// Long enough for "Kids' activities", short enough to fit a grid tile.
    public static let maxNameLength = 24
}

public protocol GetCategoriesUseCase: Sendable {
    func execute() async throws(DomainError) -> [TransactionCategory]
}

public struct DefaultGetCategoriesUseCase: GetCategoriesUseCase {
    private let categories: any CategoryRepository

    public init(categories: any CategoryRepository) {
        self.categories = categories
    }

    public func execute() async throws(DomainError) -> [TransactionCategory] {
        try await TransactionCategory.ordered(categories.fetchCategories())
    }
}

public protocol SaveCategoryUseCase: Sendable {
    func execute(_ draft: CategoryDraft) async throws(DomainError) -> TransactionCategory
}

public struct DefaultSaveCategoryUseCase: SaveCategoryUseCase {
    private let categories: any CategoryRepository

    public init(categories: any CategoryRepository) {
        self.categories = categories
    }

    public func execute(_ draft: CategoryDraft) async throws(DomainError) -> TransactionCategory {
        let name = String(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(CategoryDraft.maxNameLength))
        guard !name.isEmpty else { throw .missingName }
        guard draft.kind != .transfer else { throw .unsupportedTransactionKind(.transfer) }
        let existing = try await categories.fetchCategories()
        var kind = draft.kind
        var isRenamed = false
        if let id = draft.id {
            guard let current = existing.first(where: { $0.id == id }) else { throw .corruptedData("Category \(id)") }
            // Its movements were recorded under this kind; switching it would break them.
            kind = current.kind
            // Giving a default back its shipped name makes it translate again.
            isRenamed = TransactionCategory.shipped(id: id).map { $0.name != name } ?? false
        }
        let isTaken = existing.contains { other in
            other.id != draft.id && other.kind == kind
                && other.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        guard !isTaken else { throw .duplicateCategoryName(name) }
        // Budgets cap spending; income has nothing to cap, so a stray amount is dropped, not refused.
        let budget = kind == .expense ? draft.monthlyBudget : nil
        if let budget, budget.amount <= 0 {
            throw .invalidAmount
        }
        let category = TransactionCategory(
            id: draft.id ?? TransactionCategory.newCustomID(),
            name: name,
            kind: kind,
            icon: draft.icon,
            color: draft.color,
            isRenamed: isRenamed,
            monthlyBudget: budget,
        )
        try await categories.save(category)
        return category
    }
}

/// The currency budgets are typed and compared in. Before onboarding there are no settings and
/// no movements to budget, so `nil`.
public protocol GetPrincipalCurrencyUseCase: Sendable {
    func execute() async throws(DomainError) -> String?
}

public struct DefaultGetPrincipalCurrencyUseCase: GetPrincipalCurrencyUseCase {
    private let settings: any SettingsRepository

    public init(settings: any SettingsRepository) {
        self.settings = settings
    }

    public func execute() async throws(DomainError) -> String? {
        try await settings.load()?.currencies.principal
    }
}

/// Deletes a category, a default or one the person created. Its movements move to "Other" of the
/// same kind, so balances and summaries keep adding up.
public protocol DeleteCategoryUseCase: Sendable {
    func execute(id: String) async throws(DomainError)
}

public struct DefaultDeleteCategoryUseCase: DeleteCategoryUseCase {
    private let categories: any CategoryRepository
    private let transactions: any TransactionRepository

    public init(categories: any CategoryRepository, transactions: any TransactionRepository) {
        self.categories = categories
        self.transactions = transactions
    }

    public func execute(id: String) async throws(DomainError) {
        guard let category = try await categories.fetchCategories().first(where: { $0.id == id }) else { return }
        guard !category.isFallback else { throw .fallbackCategoryCantBeDeleted(id) }
        let otherID = TransactionCategory.otherID(for: category.kind)
        for movement in try await transactions.fetchTransactions(in: nil) where movement.categoryID == id {
            try await transactions.save(movement.with(categoryID: otherID))
        }
        try await categories.deleteCategory(id: id)
    }
}

/// Runs after every pull. A device that edited a movement (or recurring rule) before it heard of a
/// category's deletion wins with its later edit and brings the deleted id back (ADR 0005 keeps the
/// newest row whole). Whatever still points at one of `deletedCategoryIDs` (the tombstones) moves
/// to "Other" of its kind; with nothing to repair nothing is written. Returns how many records moved.
public protocol ReassignDeletedCategoriesUseCase: Sendable {
    @discardableResult
    func execute(deletedCategoryIDs: Set<String>) async throws(DomainError) -> Int
}

public struct DefaultReassignDeletedCategoriesUseCase: ReassignDeletedCategoriesUseCase {
    private let transactions: any TransactionRepository
    private let recurringRules: any RecurringRuleRepository

    public init(transactions: any TransactionRepository, recurringRules: any RecurringRuleRepository) {
        self.transactions = transactions
        self.recurringRules = recurringRules
    }

    @discardableResult
    public func execute(deletedCategoryIDs: Set<String>) async throws(DomainError) -> Int {
        guard !deletedCategoryIDs.isEmpty else { return 0 }
        func isOrphaned(_ categoryID: String?, _ kind: TransactionKind) -> Bool {
            guard kind != .transfer, let categoryID else { return false }
            let isFallback = categoryID == TransactionCategory.otherExpenseID || categoryID == TransactionCategory.otherIncomeID
            return !isFallback && deletedCategoryIDs.contains(categoryID)
        }
        let movements = try await transactions.fetchTransactions(in: nil)
            .filter { isOrphaned($0.categoryID, $0.kind) }
            .map { $0.with(categoryID: TransactionCategory.otherID(for: $0.kind)) }
        let rules = try await recurringRules.fetchRecurringRules()
            .filter { isOrphaned($0.categoryID, $0.kind) }
            .map { $0.with(categoryID: TransactionCategory.otherID(for: $0.kind)) }
        guard !movements.isEmpty || !rules.isEmpty else { return 0 }
        // One save: a failure moves nothing, and the next pull tries again.
        try await recurringRules.saveMaterialized(transactions: movements, rules: rules)
        return movements.count + rules.count
    }
}

/// Saves the order the person dragged the categories into.
public protocol ReorderCategoriesUseCase: Sendable {
    func execute(ids: [String]) async throws(DomainError)
}

public struct DefaultReorderCategoriesUseCase: ReorderCategoriesUseCase {
    private let categories: any CategoryRepository

    public init(categories: any CategoryRepository) {
        self.categories = categories
    }

    public func execute(ids: [String]) async throws(DomainError) {
        try await categories.reorderCategories(ids: ids)
    }
}

/// "Restore default categories": brings back deleted defaults and undoes renames, icons, colors
/// and order on them. Movements already moved to "Other" stay there; the person's own categories stay.
public protocol RestoreDefaultCategoriesUseCase: Sendable {
    func execute() async throws(DomainError)
}

public struct DefaultRestoreDefaultCategoriesUseCase: RestoreDefaultCategoriesUseCase {
    private let categories: any CategoryRepository

    public init(categories: any CategoryRepository) {
        self.categories = categories
    }

    public func execute() async throws(DomainError) {
        try await categories.restoreDefaultCategories()
    }
}

extension Transaction {
    /// Everything else stays, tags and the recurring rule included: moving a deleted category's
    /// movements to "Other" must not lose what else the person recorded on them.
    public func with(categoryID: String?) -> Self {
        with(categoryID: categoryID, tags: tags)
    }
}

extension RecurringRule {
    /// The same rule filed under another category; everything else stays.
    public func with(categoryID: String?) -> Self {
        Self(
            id: id, name: name, kind: kind, categoryID: categoryID, amount: amount, currency: currency,
            accountID: accountID, cardID: cardID, destinationAccountID: destinationAccountID, frequency: frequency,
            interval: interval, startDate: startDate, nextDate: nextDate, endDate: endDate,
            isSubscription: isSubscription, autoConfirm: autoConfirm, isPaused: isPaused, note: note, tags: tags,
            source: source,
        )
    }
}
