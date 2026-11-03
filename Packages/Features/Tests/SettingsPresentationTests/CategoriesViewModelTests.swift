import Domain
import DomainSamples
import Foundation
import Testing
@testable import SettingsPresentation

@Suite("Categories view model")
@MainActor
struct CategoriesViewModelTests {
    private func make(_ store: InMemoryStore, kind: TransactionKind = .expense) -> CategoriesViewModel {
        CategoriesViewModel(
            kind: kind,
            getCategories: DefaultGetCategoriesUseCase(categories: store),
            save: DefaultSaveCategoryUseCase(categories: store),
            delete: DefaultDeleteCategoryUseCase(categories: store, transactions: store, cards: store),
            reorder: DefaultReorderCategoriesUseCase(categories: store),
            restoreDefaults: DefaultRestoreDefaultCategoriesUseCase(categories: store),
        )
    }

    @Test
    func listsDefaultsAndTheirOwnTogetherByKindWithOtherLast() async {
        let boat = TransactionCategory(id: "custom-boat", name: "Boat", kind: .expense)
        let tips = TransactionCategory(id: "custom-tips", name: "Tips", kind: .income)
        let viewModel = make(InMemoryStore(categories: TransactionCategory.defaults + [boat, tips]))
        await viewModel.load()
        #expect(viewModel.visible.map(\.id) == TransactionCategory.defaultExpense.dropLast().map(\.id) + [boat.id, "other-expense"])
        viewModel.kind = .income
        #expect(viewModel.visible.suffix(2).map(\.id) == [tips.id, "other-income"])
    }

    @Test
    func everyCategoryOpensTheEditorButOtherCantBeDeleted() async throws {
        let viewModel = make(InMemoryStore())
        await viewModel.load()
        try viewModel.edit(#require(viewModel.visible.first))
        #expect(viewModel.editor?.editing?.id == "groceries")
        #expect(viewModel.editor?.canDelete == true)
        try viewModel.edit(#require(viewModel.visible.last))
        #expect(viewModel.editor?.isFallback == true)
        #expect(viewModel.editor?.canDelete == false)
    }

    @Test
    func newCategoriesTakeTheSelectedKindAndReloadAfterSaving() async throws {
        let store = InMemoryStore()
        let viewModel = make(store, kind: .income)
        await viewModel.load()
        viewModel.startNew()
        let editor = try #require(viewModel.editor)
        #expect(editor.kind == .income)
        editor.setName("Tips")
        _ = await editor.save()
        await viewModel.editorFinished()
        #expect(viewModel.editor == nil)
        #expect(viewModel.visible.suffix(2).map(\.name) == ["Tips", "Other income"])
    }

    @Test
    func movingSwapsNeighboursAndNeverPassesOther() async throws {
        let store = InMemoryStore()
        let viewModel = make(store)
        await viewModel.load()
        let groceries = try #require(viewModel.visible.first)
        #expect(!viewModel.canMove(groceries, by: -1))
        await viewModel.move(groceries, by: 1)
        #expect(viewModel.visible.prefix(2).map(\.id) == ["restaurants", "groceries"])
        let last = try #require(viewModel.visible.dropLast().last)
        #expect(!viewModel.canMove(last, by: 1))
        let other = try #require(viewModel.visible.last)
        #expect(!viewModel.canMove(other, by: -1))
        await viewModel.load()
        #expect(viewModel.visible.prefix(2).map(\.id) == ["restaurants", "groceries"])
    }

    @Test
    func restoringBringsTheDefaultsBack() async throws {
        let store = InMemoryStore()
        let viewModel = make(store)
        try await DefaultDeleteCategoryUseCase(categories: store, transactions: store, cards: store).execute(id: "groceries")
        await viewModel.load()
        #expect(!viewModel.visible.contains { $0.id == "groceries" })
        viewModel.isReordering = true
        await viewModel.restore()
        #expect(viewModel.visible == TransactionCategory.defaultExpense)
        #expect(!viewModel.isReordering)
    }
}
