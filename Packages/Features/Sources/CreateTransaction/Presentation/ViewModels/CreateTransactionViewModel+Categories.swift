import Domain
import Foundation
import SharedPresentation

/// Step 2's category grid and the "New category" tile.
extension CreateTransactionViewModel {
    public var categories: [TransactionCategory] {
        TransactionCategory.ordered(context?.categories ?? []).filter { $0.kind == kind }
    }

    /// The grid: search results, everything after "See all N", or the most used. Ties keep the
    /// shipped order, so a new person sees the everyday categories first.
    public var visibleCategories: [TransactionCategory] {
        let query = categoryQuery.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            return categories.filter { CategoryDisplay.name(of: $0).localizedStandardContains(query) }
        }
        let usage = context?.categoryUsage ?? [:]
        let ranked = categories.enumerated()
            .sorted { lhs, rhs in
                let left = usage[lhs.element.id] ?? 0
                let right = usage[rhs.element.id] ?? 0
                return left == right ? lhs.offset < rhs.offset : left > right
            }
            .map(\.element)
        return hasMoreCategories ? Array(ranked.prefix(collapsedCount)) : ranked
    }

    /// True while the grid is collapsed; the "See all" and "New category" tiles take the last two slots.
    public var hasMoreCategories: Bool {
        categoryQuery.trimmingCharacters(in: .whitespaces).isEmpty && !showsAllCategories
            && categories.count + newCategoryTiles > Self.categorySlots
    }

    private var newCategoryTiles: Int {
        canCreateCategory ? 1 : 0
    }

    private var collapsedCount: Int {
        Self.categorySlots - 1 - newCategoryTiles
    }

    // MARK: New category

    public var canCreateCategory: Bool {
        saveCategory != nil && kind != .transfer
    }

    /// Opens the editor, named after what the person searched for when nothing matched it.
    public func startNewCategory() {
        guard let saveCategory, kind != .transfer else { return }
        categoryEditor = CategoryEditorViewModel(kind: kind, name: categoryQuery.trimmingCharacters(in: .whitespaces), save: saveCategory)
    }

    /// The new category joins the grid and is chosen, the way picking any tile moves on.
    public func categoryCreated(_ category: TransactionCategory) {
        categoryEditor = nil
        context = context?.adding(category)
        categoryQuery = ""
        selectCategory(category.id)
    }
}
