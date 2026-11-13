import Domain
import DomainSamples
import FeatureTestSupport
import SettingsDomain
import SwiftUI
import Testing
@testable import SettingsPresentation

/// Settings › Businesses and a rule's editor with its business. Logos show their monograms: tests
/// have no logo loader, so nothing leaves the machine.
@Suite("Businesses snapshots")
@MainActor
struct MerchantsSnapshotTests {
    private let subway = Merchant(name: "Subway", domain: "subway.com", brandID: "subway", defaultCategoryID: "restaurants")
    private let corner = Merchant(name: "Pulpería La Esquina")
    private let uberEats = Merchant(name: "Uber Eats", domain: "ubereats.com", isPlatform: true)

    private func makeStore() -> InMemoryStore {
        let lunch = Transaction(
            date: SampleData.defaultReferenceDate, description: "Lunch", kind: .expense, categoryID: "restaurants", amount: 5,
            currency: "USD", accountID: SampleData.IDs.cash, exchangeRate: SampleData.standard.settings.currencies.exchangeRate,
            merchantID: subway.id, viaMerchantID: uberEats.id,
        )
        return InMemoryStore(transactions: [lunch], merchants: [subway, corner, uberEats])
    }

    @Test
    func merchants() async {
        let store = makeStore()
        let viewModel = MerchantsViewModel(
            manage: DefaultManageMerchantsUseCase(
                merchants: store, categories: store, transactions: store, recurringRules: store, categorizationRules: store,
            ),
            getCategories: DefaultGetCategoriesUseCase(categories: store),
        )
        await viewModel.load()
        await assertScreenSnapshot(of: MerchantsView(viewModel: viewModel, onBack: {}))
    }

    /// The business row sits under the category, naming the rule's merchant.
    @Test
    func ruleEditorWithMerchant() async throws {
        let rule = CategorizationRule(match: "Subway", categoryID: "restaurants", kind: .expense, merchantID: subway.id)
        let store = InMemoryStore(categorizationRules: [rule], merchants: [subway, corner, uberEats])
        let rules = RulesViewModel(
            manage: DefaultManageCategorizationRulesUseCase(rules: store, categories: store, transactions: store, merchants: store),
            getCategories: DefaultGetCategoriesUseCase(categories: store),
        )
        await rules.load()
        rules.edit(rule)
        let editor = try #require(rules.editor)
        await assertScreenSnapshot(of: RuleEditorView(viewModel: editor, onDone: {}, onClose: {}))
    }
}
