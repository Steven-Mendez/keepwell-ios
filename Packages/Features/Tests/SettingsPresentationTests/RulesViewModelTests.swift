import Domain
import DomainSamples
import Foundation
import Testing
@testable import SettingsPresentation

@Suite("Rules view model")
@MainActor
struct RulesViewModelTests {
    private let uber = CategorizationRule(match: "Uber", categoryID: "transport", kind: .expense)
    private let cafe = CategorizationRule(match: "Café", categoryID: "restaurants", kind: .expense, tags: ["salidas"])

    private func make(_ store: InMemoryStore) -> RulesViewModel {
        RulesViewModel(
            manage: DefaultManageCategorizationRulesUseCase(rules: store, categories: store, transactions: store),
            getCategories: DefaultGetCategoriesUseCase(categories: store),
        )
    }

    @Test
    func listsRulesInOrderAndMovesThem() async {
        let store = InMemoryStore(categorizationRules: [uber, cafe])
        let viewModel = make(store)
        await viewModel.load()
        #expect(viewModel.rules == [uber, cafe])
        #expect(viewModel.categoryName(of: uber) == "Transport")
        #expect(viewModel.detail(of: cafe) == "Expenses · #salidas")
        #expect(!viewModel.canMove(uber, by: -1))
        await viewModel.move(uber, by: 1)
        #expect(viewModel.rules == [cafe, uber])
        #expect(await store.fetchCategorizationRules() == [cafe, uber])
    }

    @Test
    func theEditorSavesARuleOnlyWithTextAndACategoryOfItsKind() async throws {
        let store = InMemoryStore()
        let viewModel = make(store)
        await viewModel.load()
        viewModel.startNew()
        let editor = try #require(viewModel.editor)
        editor.setMatch("  Netflix ")
        #expect(!editor.canSave)
        editor.categoryID = "subscriptions"
        editor.tags = ["#Casa"]
        editor.kind = .income
        #expect(editor.categoryID == nil)
        editor.kind = .expense
        editor.categoryID = "subscriptions"
        let saved = try #require(await editor.save())
        #expect(saved.match == "Netflix")
        #expect(saved.tags == ["casa"])
        #expect(await store.fetchCategorizationRules() == [saved])
    }

    /// Editing the rest keeps the merchant the rule has, also one this device hasn't pulled yet.
    @Test
    func editingARuleKeepsItsMerchant() async throws {
        let live = Merchant(name: "Uber", domain: "uber.com")
        let notPulled = UUID()
        for merchantID in [live.id, notPulled] {
            let rule = CategorizationRule(match: "Uber", categoryID: "transport", kind: .expense, merchantID: merchantID)
            let store = InMemoryStore(categorizationRules: [rule], merchants: [live])
            let viewModel = RulesViewModel(
                manage: DefaultManageCategorizationRulesUseCase(rules: store, categories: store, transactions: store, merchants: store),
                getCategories: DefaultGetCategoriesUseCase(categories: store),
            )
            await viewModel.load()
            viewModel.edit(rule)
            let editor = try #require(viewModel.editor)
            editor.setMatch("Uber trip")
            let saved = try #require(await editor.save())
            #expect(saved.match == "Uber trip")
            #expect(saved.merchantID == merchantID)
            #expect(await store.fetchCategorizationRules().first?.merchantID == merchantID)
        }
    }

    private func makeWithMerchants(_ store: InMemoryStore) -> RulesViewModel {
        RulesViewModel(
            manage: DefaultManageCategorizationRulesUseCase(rules: store, categories: store, transactions: store, merchants: store),
            getCategories: DefaultGetCategoriesUseCase(categories: store),
        )
    }

    /// A new rule can name one of the person's businesses, and an edited one can change or drop it.
    @Test
    func theEditorSavesTheBusinessItPicks() async throws {
        let subway = Merchant(name: "Subway", domain: "subway.com")
        let corner = Merchant(name: "Pulpería")
        let store = InMemoryStore(merchants: [subway, corner])
        let viewModel = makeWithMerchants(store)
        await viewModel.load()
        viewModel.startNew()
        let editor = try #require(viewModel.editor)
        #expect(editor.merchants.map(\.name) == ["Pulpería", "Subway"])
        #expect(editor.showsMerchant)
        #expect(editor.merchantID == nil)
        #expect(editor.merchantTitle == "None")
        editor.setMatch("Subway")
        editor.categoryID = "restaurants"
        editor.merchantID = subway.id
        #expect(editor.merchantTitle == "Subway")
        let created = try #require(await editor.save())
        #expect(created.merchantID == subway.id)
        #expect(await store.fetchCategorizationRules().first?.merchantID == subway.id)

        await viewModel.editorFinished()
        viewModel.edit(created)
        let changing = try #require(viewModel.editor)
        #expect(changing.merchantID == subway.id)
        changing.merchantID = corner.id
        #expect(try #require(await changing.save()).merchantID == corner.id)

        await viewModel.editorFinished()
        let changed = try #require(viewModel.rules.first)
        viewModel.edit(changed)
        let clearing = try #require(viewModel.editor)
        clearing.merchantID = nil
        #expect(try #require(await clearing.save()).merchantID == nil)
        #expect(await store.fetchCategorizationRules().first?.merchantID == nil)
    }

    /// Without businesses the field stays hidden, as on the web; a rule naming one this device
    /// hasn't pulled shows it as such.
    @Test
    func theBusinessFieldShowsOnlyWithSomethingToPick() async throws {
        let empty = makeWithMerchants(InMemoryStore())
        await empty.load()
        empty.startNew()
        #expect(try #require(empty.editor).showsMerchant == false)

        let rule = CategorizationRule(match: "Uber", categoryID: "transport", kind: .expense, merchantID: UUID())
        let store = InMemoryStore(categorizationRules: [rule])
        let viewModel = makeWithMerchants(store)
        await viewModel.load()
        viewModel.edit(rule)
        let editor = try #require(viewModel.editor)
        #expect(editor.showsMerchant)
        #expect(editor.merchantTitle == "A business not on this device yet")
    }

    @Test
    func applyingToPastAsksWithTheCountThenRecategorizes() async throws {
        let rate = try ExchangeRate(principal: "USD", second: "NIO", rate: 36)
        func movement(_ description: String, _ category: String) -> Transaction {
            Transaction(
                date: SampleData.defaultReferenceDate, description: description, kind: .expense, categoryID: category,
                amount: 5, currency: "USD", accountID: UUID(), exchangeRate: rate,
            )
        }
        let trips = [movement("Uber home", "other-expense"), movement("UBER", "other-expense"), movement("Uber Eats", "restaurants")]
        let store = InMemoryStore(transactions: trips, categorizationRules: [uber])
        let viewModel = make(store)
        await viewModel.load()
        viewModel.edit(uber)
        let editor = try #require(viewModel.editor)
        await editor.prepareApplyToPast()
        #expect(editor.pastMatchCount == 2)
        #expect(editor.applyToPastTitle == "Move 2 movements to Transport?")
        await editor.applyToPast()
        #expect(editor.appliedMessage == "2 movements updated.")
        let categories = await store.fetchTransactions(in: nil).map(\.categoryID)
        #expect(categories == ["transport", "transport", "restaurants"])
        await editor.prepareApplyToPast()
        #expect(editor.pastMatchCount == nil)
        #expect(editor.appliedMessage == "No past movements to change.")
    }
}
