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
}
