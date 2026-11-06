import Domain
import SettingsDomain
import SettingsPresentation

// MARK: - Categorization rules

extension AppContainer {
    func makeRulesViewModel() -> RulesViewModel {
        RulesViewModel(
            manage: DefaultManageCategorizationRulesUseCase(rules: store, categories: store, transactions: store),
            getCategories: DefaultGetCategoriesUseCase(categories: store),
        )
    }

    /// CSV import fills a row without a known category from the first rule it matches.
    func makeImportTransactions() -> any ImportTransactionsUseCase {
        DefaultImportTransactionsUseCase(
            transactions: store, accounts: store, cards: store, categories: store, settings: store, rules: store,
        )
    }
}
