import CreateTransactionDomain
import Domain
import DomainSamples
import Foundation
import SharedPresentation
import Testing
@testable import CreateTransactionPresentation

/// "Business" and "Via" in the movement editor (keepwell-web's `merchant-state.ts`).
@Suite("Merchant fields")
@MainActor
struct MerchantFieldsTests {
    private typealias IDs = SampleData.IDs
    private let now = SampleData.defaultReferenceDate
    private let subway = Merchant(name: "Subway", domain: "subway.com", brandID: "subway", defaultCategoryID: "restaurants")
    private let uberEats = Merchant(name: "Uber Eats", domain: "ubereats.com", brandID: "uber-eats", isPlatform: true)

    private func store() -> InMemoryStore {
        let sample = SampleData.standard
        return InMemoryStore(
            accounts: sample.accounts, cards: sample.cards, transactions: sample.transactions, categories: sample.categories,
            settings: sample.settings, recurringRules: sample.recurringRules, categorizationRules: sample.categorizationRules,
            merchants: [subway, uberEats],
        )
    }

    private func context(_ store: InMemoryStore) -> DefaultGetTransactionContextUseCase {
        DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: store, rules: store, merchants: store,
            now: { [now] in now },
        )
    }

    private func newMovement(_ store: InMemoryStore, search: (any BrandSearching)? = nil) async -> CreateTransactionViewModel {
        let context = context(store)
        let viewModel = CreateTransactionViewModel(
            getContext: context,
            save: DefaultSaveTransactionUseCase(context: context, transactions: store, merchants: store),
            brandSearch: search,
            now: { [now] in now },
        )
        await viewModel.load()
        return viewModel
    }

    @Test
    func theDescriptionSuggestsTheBusinessAndItsCategoryUntilThePersonChooses() async {
        let viewModel = await newMovement(store())
        #expect(viewModel.showsMerchantFields)
        viewModel.description = "Subway lunch"
        #expect(viewModel.businessChoice == .merchant(subway.id))
        #expect(viewModel.categoryID == "restaurants")
        // Another text takes the suggestion, and the category it brought, back.
        viewModel.description = "Pan dulce"
        #expect(viewModel.businessChoice == nil)
        #expect(viewModel.categoryID == nil)
        // A brand of the table that isn't a merchant yet is one to create on save.
        viewModel.description = "Netflix"
        #expect(viewModel.businessChoice == .new(MerchantDraft(name: "Netflix", domain: "netflix.com", brandID: "netflix")))
        // Once the person clears it, no suggestion replaces it.
        viewModel.chooseBusiness(nil)
        viewModel.description = "Subway again"
        #expect(viewModel.businessChoice == nil)
    }

    @Test
    func aCategoryThePersonPickedStays() async {
        let viewModel = await newMovement(store())
        viewModel.selectCategory("groceries")
        viewModel.chooseBusiness(.merchant(subway.id))
        #expect(viewModel.categoryID == "groceries")
        #expect(viewModel.businessName == "Subway")
    }

    @Test
    func choosingTheBusinessBringsItsDefaultCategory() async {
        let viewModel = await newMovement(store())
        viewModel.chooseBusiness(.merchant(subway.id))
        #expect(viewModel.categoryID == "restaurants")
        viewModel.chooseBusiness(.merchant(uberEats.id))
        #expect(viewModel.categoryID == nil)
    }

    @Test
    func theViaPickerNeverOffersTheBusinessAndTheSameMerchantIsntBoth() async {
        let viewModel = await newMovement(store())
        viewModel.chooseBusiness(.merchant(subway.id))
        viewModel.openViaPicker()
        let picker = viewModel.merchantPicker
        #expect(picker?.role == .via)
        #expect(picker?.options.map(\.label) == ["Uber Eats"])
        if let option = picker?.options.first {
            picker?.pick(option)
        }
        #expect(viewModel.viaChoice == .merchant(uberEats.id))
        #expect(viewModel.viaName == "Uber Eats")
        #expect(viewModel.merchantPicker == nil)
        // Making the platform the business drops it as platform.
        viewModel.chooseBusiness(.merchant(uberEats.id))
        #expect(viewModel.viaChoice == nil)
    }

    @Test
    func theBusinessPickerSearchesTheWebWhenNothingLocalMatches() async {
        let search = FakeSearch(results: [BrandSearchResult(name: "Qwertz Café", domain: "qwertz.com")])
        let viewModel = await newMovement(store(), search: search)
        viewModel.openBusinessPicker()
        let picker = viewModel.merchantPicker
        #expect(picker?.role == .business)
        picker?.query = "qwertz"
        await picker?.waitForSearch()
        #expect(picker?.options.contains { $0.group == .web && $0.label == "Qwertz Café" } == true)
    }

    @Test
    func savingCreatesThePickedMerchantsAndLinksThem() async throws {
        let store = store()
        let viewModel = await newMovement(store)
        viewModel.chooseBusiness(.new(MerchantDraft(name: "Papa John's", domain: "papajohns.com")))
        viewModel.chooseVia(.merchant(uberEats.id))
        viewModel.selectSource(.account(IDs.cash))
        viewModel.amountText = "250"
        await viewModel.save()
        let saved = try #require(viewModel.saved?.transaction)
        let created = try #require(try await store.fetchMerchants().first { $0.name == "Papa John's" })
        #expect(saved.merchantID == created.id)
        #expect(saved.viaMerchantID == uberEats.id)
    }

    @Test
    func anEditOpensWithTheLinksAndClearingOneUnlinksIt() async throws {
        let store = store()
        let movement = Transaction(
            date: now, description: "Lunch", kind: .expense, categoryID: "groceries", amount: 10, currency: "NIO",
            accountID: IDs.cash, exchangeRate: SampleData.standard.settings.currencies.exchangeRate,
            merchantID: subway.id, viaMerchantID: uberEats.id,
        )
        await store.save(movement)
        let stored = context(store)
        let viewModel = CreateTransactionViewModel(
            stored: .edit(movement.id),
            getStored: stored,
            update: DefaultUpdateTransactionUseCase(stored: stored, transactions: store, settings: store, merchants: store),
        )
        await viewModel.load()
        #expect(viewModel.businessChoice == .merchant(subway.id))
        #expect(viewModel.viaChoice == .merchant(uberEats.id))
        // An edit never takes a suggestion from the text, nor the business's category.
        viewModel.description = "Netflix"
        #expect(viewModel.businessChoice == .merchant(subway.id))
        #expect(viewModel.categoryID == "groceries")
        viewModel.chooseVia(nil)
        await viewModel.saveChanges()
        let edited = try #require(try await store.fetchTransactions(in: nil).first { $0.id == movement.id })
        #expect(edited.merchantID == subway.id)
        #expect(edited.viaMerchantID == nil)
    }

    /// Without merchants loaded (a caller that doesn't know them) the fields hide and the links stay.
    @Test
    func withoutMerchantsTheFieldsHideAndKeepTheLinks() async {
        let viewModel = await CreateTransactionFactory.loaded()
        #expect(!viewModel.showsMerchantFields)
        viewModel.description = "Subway"
        #expect(viewModel.businessChoice == nil)
    }
}

/// A brand search that answers at once and records what it was asked.
final class FakeSearch: BrandSearching, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [String] = []
    let results: [BrandSearchResult]

    init(results: [BrandSearchResult]) {
        self.results = results
    }

    var queries: [String] {
        lock.withLock { asked }
    }

    func search(_ text: String) async -> [BrandSearchResult] {
        lock.withLock { asked.append(text) }
        return results
    }
}
