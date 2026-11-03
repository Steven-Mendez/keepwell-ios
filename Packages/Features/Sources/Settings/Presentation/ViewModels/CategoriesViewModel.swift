import Domain
import Foundation
import Observation
import SharedPresentation

/// Settings › Categories: every category of one kind, where the person creates their own and
/// renames, recolors or deletes them. Defaults are listed so the whole set is visible, but stay fixed.
@MainActor
@Observable
public final class CategoriesViewModel {
    public var kind: TransactionKind
    public private(set) var categories: [TransactionCategory] = []
    public private(set) var errorMessage: String?
    public var editor: CategoryEditorViewModel?

    private let getCategories: any GetCategoriesUseCase
    private let saveCategory: any SaveCategoryUseCase
    private let deleteCategory: any DeleteCategoryUseCase

    public init(
        kind: TransactionKind = .expense,
        getCategories: any GetCategoriesUseCase,
        save: any SaveCategoryUseCase,
        delete: any DeleteCategoryUseCase,
    ) {
        self.kind = kind == .income ? .income : .expense
        self.getCategories = getCategories
        saveCategory = save
        deleteCategory = delete
    }

    public func load() async {
        do {
            categories = try await getCategories.execute()
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "We couldn't load your categories.", bundle: #bundle)
        }
    }

    public var custom: [TransactionCategory] {
        categories.filter { $0.kind == kind && !$0.isDefault }
    }

    public var defaults: [TransactionCategory] {
        categories.filter { $0.kind == kind && $0.isDefault }
    }

    public func startNew() {
        editor = CategoryEditorViewModel(kind: kind, save: saveCategory)
    }

    public func edit(_ category: TransactionCategory) {
        guard !category.isDefault else { return }
        editor = CategoryEditorViewModel(editing: category, save: saveCategory, delete: deleteCategory)
    }

    /// Called after the editor saved or deleted, so the list shows the stored result.
    public func editorFinished() async {
        editor = nil
        await load()
    }
}
