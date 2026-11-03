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
            delete: DefaultDeleteCategoryUseCase(categories: store, transactions: store),
        )
    }

    @Test
    func listsTheirOwnApartFromTheDefaultsByKind() async {
        let boat = TransactionCategory(id: "custom-boat", name: "Boat", kind: .expense)
        let tips = TransactionCategory(id: "custom-tips", name: "Tips", kind: .income)
        let viewModel = make(InMemoryStore(categories: TransactionCategory.defaults + [boat, tips]))
        await viewModel.load()
        #expect(viewModel.custom == [boat])
        #expect(viewModel.defaults == TransactionCategory.defaultExpense)
        viewModel.kind = .income
        #expect(viewModel.custom == [tips])
    }

    @Test
    func onlyCreatedCategoriesOpenTheEditor() async throws {
        let boat = TransactionCategory(id: "custom-boat", name: "Boat", kind: .expense)
        let viewModel = make(InMemoryStore(categories: TransactionCategory.defaults + [boat]))
        await viewModel.load()
        try viewModel.edit(#require(viewModel.defaults.first))
        #expect(viewModel.editor == nil)
        viewModel.edit(boat)
        #expect(viewModel.editor?.editing == boat)
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
        #expect(viewModel.custom.map(\.name) == ["Tips"])
    }
}
