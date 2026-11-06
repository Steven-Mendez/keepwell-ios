import Domain
import Foundation
import Observation
import SharedPresentation

/// Settings › Categories: one editable list per kind. Every category, shipped or created, can be
/// renamed, restyled, reordered and deleted; "Other" can't be deleted because deleting sends
/// movements there. "Restore default categories" undoes what was done to the shipped ones.
@MainActor
@Observable
public final class CategoriesViewModel {
    public var kind: TransactionKind {
        didSet { isReordering = false }
    }

    public private(set) var categories: [TransactionCategory] = []
    public private(set) var errorMessage: String?
    public var editor: CategoryEditorViewModel?
    public var isReordering = false

    private let getCategories: any GetCategoriesUseCase
    private let saveCategory: any SaveCategoryUseCase
    private let deleteCategory: any DeleteCategoryUseCase
    private let reorderCategories: any ReorderCategoriesUseCase
    private let restoreDefaults: any RestoreDefaultCategoriesUseCase

    public init(
        kind: TransactionKind = .expense,
        getCategories: any GetCategoriesUseCase,
        save: any SaveCategoryUseCase,
        delete: any DeleteCategoryUseCase,
        reorder: any ReorderCategoriesUseCase,
        restoreDefaults: any RestoreDefaultCategoriesUseCase,
    ) {
        self.kind = kind == .income ? .income : .expense
        self.getCategories = getCategories
        saveCategory = save
        deleteCategory = delete
        reorderCategories = reorder
        self.restoreDefaults = restoreDefaults
    }

    public func load() async {
        do {
            categories = try await getCategories.execute()
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "We couldn't load your categories.", bundle: #bundle)
        }
    }

    /// The selected kind's categories, "Other" last.
    public var visible: [TransactionCategory] {
        categories.filter { $0.kind == kind }
    }

    /// What "Other" of the selected kind is called now; it may have been renamed.
    public var fallbackName: String {
        visible.first(where: \.isFallback).map(CategoryDisplay.name(of:)) ?? CategoryDisplay.shippedFallbackName(for: kind)
    }

    public func startNew() {
        editor = CategoryEditorViewModel(kind: kind, save: saveCategory)
    }

    public func edit(_ category: TransactionCategory) {
        editor = CategoryEditorViewModel(
            editing: category,
            fallbackName: fallbackName,
            save: saveCategory,
            delete: deleteCategory,
        )
    }

    /// Called after the editor saved or deleted, so the list shows the stored result.
    public func editorFinished() async {
        editor = nil
        await load()
    }

    /// "Other" stays last, so it has no arrows and nothing moves below it.
    public func canMove(_ category: TransactionCategory, by offset: Int) -> Bool {
        let movable = visible.filter { !$0.isFallback }
        guard let index = movable.firstIndex(of: category) else { return false }
        return movable.indices.contains(index + offset)
    }

    /// Moves one row up (`-1`) or down (`1`) and stores the new order.
    public func move(_ category: TransactionCategory, by offset: Int) async {
        guard canMove(category, by: offset) else { return }
        var movable = visible.filter { !$0.isFallback }
        guard let index = movable.firstIndex(of: category) else { return }
        movable.swapAt(index, index + offset)
        let ids = movable.map(\.id) + categories.filter { $0.kind != kind || $0.isFallback }.map(\.id)
        let previous = categories
        // Shown at once, so tapping an arrow several times doesn't wait on storage.
        categories = TransactionCategory.ordered(ids.compactMap { id in previous.first { $0.id == id } })
        do {
            try await reorderCategories.execute(ids: ids)
            errorMessage = nil
        } catch {
            categories = previous
            errorMessage = String(localized: "We couldn't save the new order. Try again.", bundle: #bundle)
        }
    }

    public func restore() async {
        do {
            try await restoreDefaults.execute()
            isReordering = false
            await load()
        } catch {
            errorMessage = String(localized: "We couldn't restore the default categories. Try again.", bundle: #bundle)
        }
    }
}
