import AccountsPresentation
import Core
import Domain
import SettingsPresentation
import SwiftUI
import TransactionsPresentation

extension RootView {
    // MARK: - Routes

    @ViewBuilder
    func destination(_ route: AppRoute) -> some View {
        switch route {
        case .settings:
            SettingsRoute(
                container: container,
                onBack: settingsClosed,
                onErased: returnToOnboarding,
                onOpenCategories: { navigator.push(.categories(showsIncome: $0 == .income)) },
            )
        case let .categories(showsIncome):
            CategoriesRoute(container: container, kind: showsIncome ? .income : .expense, onBack: navigator.pop)
        case let .creditCard(accountID, addsAdditional):
            CreditCardRoute(
                container: container,
                accountID: accountID,
                addsAdditional: addsAdditional,
                onBack: navigator.pop,
                onPay: { presentNewMovement(.cardPayment, payingCard: accountID) },
                onOpenAdditional: { navigator.push(.additionalCard(accountID: accountID, cardID: $0)) },
                onSeeAllMovements: { navigator.push(.transactions(accountID: accountID)) },
            )
        case let .additionalCard(accountID, cardID):
            AdditionalCardRoute(container: container, accountID: accountID, cardID: cardID, onBack: navigator.pop)
        case let .bankAccount(accountID):
            DebitCardRoute(
                container: container,
                accountID: accountID,
                onBack: navigator.pop,
                onSeeAllMovements: { navigator.push(.transactions(accountID: $0)) },
            )
        case let .transactions(accountID):
            TransactionsRoute(
                container: container,
                scope: accountID.map(TransactionScope.account) ?? .all,
                onBack: navigator.pop,
                onNewMovement: { presentMovementMenu() },
            )
        }
    }
}
