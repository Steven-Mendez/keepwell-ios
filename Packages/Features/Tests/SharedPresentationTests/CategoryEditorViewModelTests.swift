import Domain
import DomainSamples
import Foundation
import Testing
@testable import SharedPresentation

@Suite("Category editor view model")
@MainActor
struct CategoryEditorViewModelTests {
    @Test
    func creatingSavesTheChosenNameIconAndColor() async throws {
        let store = InMemoryStore()
        let viewModel = CategoryEditorViewModel(kind: .income, name: "Tips", save: DefaultSaveCategoryUseCase(categories: store))
        #expect(viewModel.isCreating)
        #expect(viewModel.canSave)
        viewModel.icon = "star"
        viewModel.color = "green"
        let saved = try #require(await viewModel.save())
        #expect(saved.name == "Tips")
        #expect(saved.kind == .income)
        #expect(saved.icon == "star")
        #expect(saved.color == "green")
    }

    @Test
    func namesAreCutAtTheLimitAndBlankOnesCantBeSaved() {
        let viewModel = CategoryEditorViewModel(kind: .expense, save: DefaultSaveCategoryUseCase(categories: InMemoryStore()))
        #expect(!viewModel.canSave)
        viewModel.setName(String(repeating: "a", count: 40))
        #expect(viewModel.name.count == CategoryDraft.maxNameLength)
    }

    @Test
    func aDuplicateNameShowsAMessage() async {
        let viewModel = CategoryEditorViewModel(
            kind: .expense,
            name: "Groceries",
            save: DefaultSaveCategoryUseCase(categories: InMemoryStore()),
        )
        #expect(await viewModel.save() == nil)
        #expect(viewModel.errorMessage == "You already have a category with that name.")
        viewModel.setName("Groceries 2")
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func editingStartsFromTheCategoryAndCanDelete() async {
        let boat = TransactionCategory(id: "custom-boat", name: "Boat", kind: .expense, icon: "sailboat", color: "cyan")
        let store = InMemoryStore(categories: TransactionCategory.defaults + [boat])
        let viewModel = CategoryEditorViewModel(
            editing: boat,
            save: DefaultSaveCategoryUseCase(categories: store),
            delete: DefaultDeleteCategoryUseCase(categories: store, transactions: store),
        )
        #expect(!viewModel.isCreating)
        #expect(viewModel.canDelete)
        #expect(viewModel.icon == "sailboat")
        #expect(viewModel.color == "cyan")
        #expect(await viewModel.delete())
        #expect(await store.fetchCategories().contains(boat) == false)
    }
}
