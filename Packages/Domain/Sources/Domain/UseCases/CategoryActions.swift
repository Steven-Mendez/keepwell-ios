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

    public init(id: String? = nil, name: String, kind: TransactionKind, icon: String? = nil, color: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.icon = icon
        self.color = color
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
        let category = TransactionCategory(
            id: draft.id ?? TransactionCategory.newCustomID(),
            name: name,
            kind: kind,
            icon: draft.icon,
            color: draft.color,
            isRenamed: isRenamed,
        )
        try await categories.save(category)
        return category
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
    public func with(categoryID: String?) -> Self {
        Self(
            id: id, date: date, status: status, description: description, kind: kind, categoryID: categoryID,
            amount: amount, currency: currency, accountID: accountID, cardID: cardID,
            destinationAccountID: destinationAccountID, actualDebitedPrincipal: actualDebitedPrincipal,
            exchangeRate: exchangeRate, isShared: isShared, note: note,
        )
    }
}
