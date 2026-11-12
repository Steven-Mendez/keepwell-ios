import AccountsPresentation
import Core
import Domain
import Foundation
import HomePresentation
import PlanPresentation
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
            PaymentMethodsRoute(container: container, onBack: navigator.pop, onOpenAccount: openAccount)
        case .creditCard, .bankAccount, .cash:
            accountRoute(route)
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
        case .notifications:
            notificationsRoute
        }
    }

    /// The screen of one account, split out of `destination` to keep each switch short.
    @ViewBuilder
    private func accountRoute(_ route: AppRoute) -> some View {
        switch route {
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
        case let .cash(accountID):
            CashRoute(
                container: container,
                accountID: accountID,
                onBack: navigator.pop,
                onSeeAllMovements: { navigator.push(.transactions(accountID: $0)) },
            )
        default:
            EmptyView()
        }
    }

    private func openAccount(_ account: Account) {
        switch account.kind {
        case .credit: navigator.push(.creditCard(accountID: account.id))
        case .cash: navigator.push(.cash(accountID: account.id))
        case .deposit: navigator.push(.bankAccount(accountID: account.id))
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
            onOpenRules: { navigator.push(.categorizationRules) },
            onShowKeyboardShortcuts: { perform(.showShortcuts) },
        )
    }
}

extension RootView {
    @ViewBuilder
    var notificationsRoute: some View {
        if let home = screens?.home {
            NotificationsRoute(viewModel: home, onBack: navigator.pop, onOpen: openNotification)
        }
    }

    func openNotification(_ destination: InboxItem.Destination) {
        switch destination {
        case let .transaction(id):
            navigator.push(.transaction(id: id))
        case let .creditCard(accountID):
            navigator.push(.creditCard(accountID: accountID))
        case let .account(id):
            if let account = screens?.home.overview?.accounts.first(where: { $0.id == id }) {
                openAccount(account)
            }
        case .debts:
            navigator.push(.debts)
        case .recurring:
            navigator.push(.recurring)
        case .summary:
            // A tab isn't pushed, so leave the stack to show it.
            navigator.path = NavigationPath()
            tab = .summary
        }
    }

    /// A tag tapped in a movement's detail: Transactions, narrowed to it, as the web does.
    func showTag(_ tag: String) {
        navigator.path = NavigationPath()
        screens?.transactions.showOnly(tag: tag)
        tab = .transactions
    }

    func planTab(_ screens: MainScreens) -> some View {
        PlanView(
            viewModel: screens.plan,
            onOpenRecurring: { navigator.push(.recurring) },
            onOpenGoals: { navigator.push(.goals) },
            onOpenDebts: { navigator.push(.debts) },
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
