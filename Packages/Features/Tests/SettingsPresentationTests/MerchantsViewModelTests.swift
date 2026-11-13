import Domain
import DomainSamples
import Foundation
import Testing
@testable import SettingsPresentation

/// Settings › Businesses: rename, default category, platform, merge and delete.
@Suite("Businesses view model")
@MainActor
struct MerchantsViewModelTests {
    private let subway = Merchant(name: "Subway", domain: "subway.com", brandID: "subway", defaultCategoryID: "restaurants")
    private let subwayCopy = Merchant(name: "subway centro")
    private let uberEats = Merchant(name: "Uber Eats", domain: "ubereats.com", isPlatform: true)

    private func make(_ store: InMemoryStore) -> MerchantsViewModel {
        MerchantsViewModel(
            manage: DefaultManageMerchantsUseCase(
                merchants: store, categories: store, transactions: store, recurringRules: store, categorizationRules: store,
            ),
            getCategories: DefaultGetCategoriesUseCase(categories: store),
        )
    }

    private func movement(_ merchantID: UUID?, via: UUID? = nil) -> Transaction {
        Transaction(
            date: SampleData.defaultReferenceDate, description: "Lunch", kind: .expense, categoryID: "restaurants", amount: 5,
            currency: "USD", accountID: UUID(), exchangeRate: SampleData.standard.settings.currencies.exchangeRate,
            merchantID: merchantID, viaMerchantID: via,
        )
    }

    @Test
    func listsByNameWithWhatEachOneIs() async {
        let store = InMemoryStore(transactions: [movement(subway.id, via: uberEats.id)], merchants: [uberEats, subwayCopy, subway])
        let viewModel = make(store)
        await viewModel.load()
        #expect(viewModel.merchants.map(\.name) == ["Subway", "subway centro", "Uber Eats"])
        #expect(viewModel.detail(of: subway) == "Restaurants · 1 movement")
        #expect(viewModel.detail(of: uberEats) == "Platform · 1 movement")
        #expect(viewModel.logo(of: subway)?.domain == "subway.com")
    }

    @Test
    func theEditorRenamesSetsTheCategoryAndThePlatform() async throws {
        let store = InMemoryStore(merchants: [subway])
        let viewModel = make(store)
        await viewModel.load()
        viewModel.edit(subway)
        let editor = try #require(viewModel.editor)
        #expect(!editor.categories.contains { $0.kind == .transfer })
        editor.name = "  Subway  Galerías "
        editor.defaultCategoryID = "groceries"
        editor.isPlatform = true
        #expect(await editor.save())
        await viewModel.editorFinished()
        let saved = try #require(viewModel.merchants.first)
        #expect(saved.name == "Subway Galerías")
        #expect(saved.defaultCategoryID == "groceries")
        #expect(saved.isPlatform)
        #expect(saved.brandID == "subway")
        #expect(viewModel.editor == nil)
    }

    @Test
    func theEditorExplainsWhatCantBeSaved() async throws {
        let viewModel = make(InMemoryStore(merchants: [subway]))
        await viewModel.load()
        viewModel.edit(subway)
        let editor = try #require(viewModel.editor)
        editor.name = " "
        #expect(!editor.canSave)
        editor.name = "Subway"
        editor.domain = "not a web address"
        #expect(await editor.save() == false)
        #expect(editor.errorMessage == "That isn't a web address, like subway.com.")
    }

    @Test
    func mergeAndDelete() async throws {
        let store = InMemoryStore(transactions: [movement(subwayCopy.id)], merchants: [subway, subwayCopy, uberEats])
        let viewModel = make(store)
        await viewModel.load()
        viewModel.edit(subwayCopy)
        let editor = try #require(viewModel.editor)
        #expect(editor.mergeTargets.map(\.name) == ["Subway", "Uber Eats"])
        #expect(await editor.merge(into: subway))
        #expect(try await store.fetchTransactions(in: nil).first?.merchantID == subway.id)

        await viewModel.editorFinished()
        viewModel.edit(subway)
        #expect(await viewModel.editor?.delete() == true)
        await viewModel.editorFinished()
        #expect(viewModel.merchants == [uberEats])
        #expect(try await store.fetchTransactions(in: nil).first?.merchantID == nil)
    }
}
