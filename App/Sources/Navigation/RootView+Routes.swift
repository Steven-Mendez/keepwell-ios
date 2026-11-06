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
                onOpenPaymentMethods: { navigator.push(.paymentMethods) },
            )
        case let .categories(showsIncome):
            CategoriesRoute(container: container, kind: showsIncome ? .income : .expense, onBack: navigator.pop)
        case .paymentMethods:
            PaymentMethodsRoute(container: container, onBack: navigator.pop) { account in
                navigator.push(account.kind == .credit ? .creditCard(accountID: account.id) : .bankAccount(accountID: account.id))
            }
        case let .creditCard(accountID):
            CreditCardRoute(
                container: container,
                accountID: accountID,
                onBack: navigator.pop,
                onPay: { presentNewMovement(.cardPayment, payingCard: accountID) },
                onSeeAllMovements: { navigator.push(.transactions(accountID: accountID)) },
            )
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
