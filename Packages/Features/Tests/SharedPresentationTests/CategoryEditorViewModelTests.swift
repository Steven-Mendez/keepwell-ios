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

    @Test
    func editingAnUntouchedDefaultKeepsItTranslatingAndItsShippedIcon() async throws {
        let store = InMemoryStore()
        let groceries = try #require(await store.fetchCategories().first { $0.id == "groceries" })
        let viewModel = CategoryEditorViewModel(
            editing: groceries,
            save: DefaultSaveCategoryUseCase(categories: store),
            delete: DefaultDeleteCategoryUseCase(categories: store, transactions: store),
        )
        #expect(viewModel.canDelete)
        #expect(viewModel.color == nil)
        viewModel.color = "green"
        let saved = try #require(await viewModel.save())
        #expect(saved.translatesByID)
        #expect(saved.icon == nil)
        #expect(saved.color == "green")

        viewModel.setName("Market")
        let renamed = try #require(await viewModel.save())
        #expect(renamed.isRenamed)
        #expect(renamed.name == "Market")
    }

    @Test
    func otherCanBeEditedButNotDeleted() async throws {
        let store = InMemoryStore()
        let other = try #require(await store.fetchCategories().first(where: \.isFallback))
        let viewModel = CategoryEditorViewModel(
            editing: other,
            fallbackName: "Misc",
            save: DefaultSaveCategoryUseCase(categories: store),
            delete: DefaultDeleteCategoryUseCase(categories: store, transactions: store),
        )
        #expect(viewModel.isFallback)
        #expect(!viewModel.canDelete)
        #expect(viewModel.fallbackName == "Misc")
        #expect(await viewModel.delete() == false)
    }

    @Test
    func anExpenseBudgetIsSavedInThePrincipalCurrencyAndEmptyMeansNone() async throws {
        let store = InMemoryStore()
        let viewModel = CategoryEditorViewModel(
            kind: .expense, name: "Boat", principalCurrency: "NIO", save: DefaultSaveCategoryUseCase(categories: store),
        )
        #expect(viewModel.showsBudget)
        #expect(viewModel.budgetText.isEmpty)
        #expect(viewModel.budgetFooter == "Summary shows how much is left, and Home warns you at 80% and 100%.")
        viewModel.budgetText = "1,250.50"
        let saved = try #require(await viewModel.save())
        #expect(saved.monthlyBudget == Money(Decimal(string: "1250.5") ?? 0, "NIO"))

        let editor = CategoryEditorViewModel(
            editing: saved, principalCurrency: "NIO",
            save: DefaultSaveCategoryUseCase(categories: store),
            delete: DefaultDeleteCategoryUseCase(categories: store, transactions: store),
        )
        #expect(editor.budgetText == "1,250.50")
        editor.budgetText = ""
        #expect(try #require(await editor.save()).monthlyBudget == nil)
    }

    @Test
    func aZeroOrUnreadableBudgetCantBeSaved() {
        let viewModel = CategoryEditorViewModel(
            kind: .expense, name: "Boat", principalCurrency: "USD", save: DefaultSaveCategoryUseCase(categories: InMemoryStore()),
        )
        viewModel.budgetText = "0"
        #expect(!viewModel.canSave)
        viewModel.budgetText = "12abc"
        #expect(!viewModel.canSave)
        viewModel.budgetText = "12"
        #expect(viewModel.canSave)
    }

    @Test
    func incomeCategoriesHaveNoBudget() {
        let viewModel = CategoryEditorViewModel(
            kind: .income, name: "Tips", principalCurrency: "USD", save: DefaultSaveCategoryUseCase(categories: InMemoryStore()),
        )
        #expect(!viewModel.showsBudget)
    }

    /// A budget set before the person changed their principal isn't shown as today's, and is
    /// kept as it was unless they type a new one.
    @Test
    func aBudgetInAnEarlierPrincipalIsKeptUntilReplaced() async throws {
        let old = Money(500, "USD")
        let boat = TransactionCategory(id: "custom-boat", name: "Boat", kind: .expense, monthlyBudget: old)
        let store = InMemoryStore(categories: TransactionCategory.defaults + [boat])
        let viewModel = CategoryEditorViewModel(
            editing: boat, principalCurrency: "NIO",
            save: DefaultSaveCategoryUseCase(categories: store),
            delete: DefaultDeleteCategoryUseCase(categories: store, transactions: store),
        )
        #expect(viewModel.budgetText.isEmpty)
        #expect(try #require(await viewModel.save()).monthlyBudget == old)
        viewModel.budgetText = "18000"
        #expect(try #require(await viewModel.save()).monthlyBudget == Money(18000, "NIO"))
    }
}
