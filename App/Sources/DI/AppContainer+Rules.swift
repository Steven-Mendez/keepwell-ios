import Domain
import SettingsDomain
import SettingsPresentation

// MARK: - Categorization rules

extension AppContainer {
    func makeRulesViewModel() -> RulesViewModel {
        RulesViewModel(
            manage: DefaultManageCategorizationRulesUseCase(
                rules: store, categories: store, transactions: movements, merchants: store,
            ),
            getCategories: DefaultGetCategoriesUseCase(categories: store),
        )
    }
}

// MARK: - Merchants

extension AppContainer {
    func makeMerchantsViewModel() -> MerchantsViewModel {
        MerchantsViewModel(
            manage: DefaultManageMerchantsUseCase(
                merchants: store, categories: store, transactions: store, recurringRules: store, categorizationRules: store,
            ),
            getCategories: DefaultGetCategoriesUseCase(categories: store),
        )
    }
}
