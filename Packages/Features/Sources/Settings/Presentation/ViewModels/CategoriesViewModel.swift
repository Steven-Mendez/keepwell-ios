import Core
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
    /// What budgets are typed and shown in; `nil` until loaded, or before onboarding.
    public private(set) var principalCurrency: String?

    private let getCategories: any GetCategoriesUseCase
    private let saveCategory: any SaveCategoryUseCase
    private let deleteCategory: any DeleteCategoryUseCase
    private let reorderCategories: any ReorderCategoriesUseCase
    private let restoreDefaults: any RestoreDefaultCategoriesUseCase
    private let getPrincipalCurrency: (any GetPrincipalCurrencyUseCase)?

    public init(
        kind: TransactionKind = .expense,
        getCategories: any GetCategoriesUseCase,
        save: any SaveCategoryUseCase,
        delete: any DeleteCategoryUseCase,
        reorder: any ReorderCategoriesUseCase,
        restoreDefaults: any RestoreDefaultCategoriesUseCase,
        getPrincipalCurrency: (any GetPrincipalCurrencyUseCase)? = nil,
    ) {
        self.kind = kind == .income ? .income : .expense
        self.getCategories = getCategories
        saveCategory = save
        deleteCategory = delete
        reorderCategories = reorder
        self.restoreDefaults = restoreDefaults
        self.getPrincipalCurrency = getPrincipalCurrency
    }

    public func load() async {
        do {
            categories = try await getCategories.execute()
            principalCurrency = try await getPrincipalCurrency?.execute()
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
        editor = CategoryEditorViewModel(kind: kind, principalCurrency: principalCurrency, save: saveCategory)
    }

    public func edit(_ category: TransactionCategory) {
        editor = CategoryEditorViewModel(
            editing: category,
            fallbackName: fallbackName,
            principalCurrency: principalCurrency,
            save: saveCategory,
            delete: deleteCategory,
        )
    }

    /// The budget under a category's name, only when it is in today's principal currency: one
    /// left in an earlier principal no longer counts anywhere.
    public func budgetLine(of category: TransactionCategory) -> String? {
        guard let budget = category.monthlyBudget, budget.currency == principalCurrency else { return nil }
        return CurrencyFormatter().string(from: budget.amount, currencyCode: budget.currency)
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
