import AccountsPresentation
import Core
import Domain
import Foundation
import SettingsPresentation
import SwiftUI
import TransactionsPresentation

extension RootView {
    // MARK: - Routes

    @ViewBuilder
    func destination(_ route: AppRoute) -> some View {
        switch route {
        case .settings:
            settingsRoute
        case let .categories(showsIncome):
            CategoriesRoute(container: container, kind: showsIncome ? .income : .expense, onBack: navigator.pop)
        case .categorizationRules:
            RulesRoute(container: container, onBack: navigator.pop)
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
            transactionsRoute(accountID: accountID)
        case let .transaction(id):
            transactionDetailRoute(id: id)
        case .recurring:
            RecurringRoute(
                container: container,
                onBack: navigator.pop,
                onAdd: { navigator.push(.recurringRule(id: nil)) },
                onOpen: { navigator.push(.recurringRule(id: $0)) },
            )
        case let .recurringRule(id):
            RecurringRuleRoute(
                container: container,
                ruleID: id,
                onBack: navigator.pop,
                onOpenTransaction: { navigator.push(.transaction(id: $0)) },
            )
        case .goals:
            GoalsRoute(container: container, onBack: navigator.pop)
        case .debts:
            DebtsRoute(container: container, onBack: navigator.pop)
        }
    }

    private func transactionsRoute(accountID: UUID?) -> some View {
        TransactionsRoute(
            container: container,
            scope: accountID.map(TransactionScope.account) ?? .all,
            onBack: navigator.pop,
            onOpenTransaction: { navigator.push(.transaction(id: $0)) },
            onOpenRecurringRule: { navigator.push(.recurringRule(id: $0)) },
            onNewMovement: { presentMovementMenu() },
        )
    }

    private func transactionDetailRoute(id: UUID) -> some View {
        TransactionDetailRoute(
            container: container,
            id: id,
            onBack: navigator.pop,
            onOpenRecurringRule: { navigator.push(.recurringRule(id: $0)) },
            onShowTag: showTag,
        )
    }

    private var settingsRoute: some View {
        SettingsRoute(
            container: container,
            onBack: settingsClosed,
            onErased: returnToOnboarding,
            onOpenCategories: { navigator.push(.categories(showsIncome: $0 == .income)) },
            onOpenPaymentMethods: { navigator.push(.paymentMethods) },
            onOpenRecurring: { navigator.push(.recurring) },
            onOpenRules: { navigator.push(.categorizationRules) },
        )
    }
}

extension RootView {
    /// The first sync with an account found data on both sides; "Decide later" closes the sheet and
    /// Settings opens it again.
    var choosingSyncData: Binding<Bool> {
        Binding(
            get: { container.cloudAccount?.sync.map { $0.isChoosingData && $0.conflict != nil } ?? false },
            set: { presented in
                if !presented {
                    container.cloudAccount?.sync?.decideLater()
                }
            },
        )
    }
}
