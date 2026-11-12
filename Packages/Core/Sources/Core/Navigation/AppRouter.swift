import Observation
import SwiftUI

/// Every pushable destination. Cases carry identifiers, never models, so a path stays cheap to
/// store and can later be encoded for state restoration.
public enum AppRoute: Hashable, Sendable {
    case settings
    /// Settings › Categories, opened on the income tab or the expense one.
    case categories(showsIncome: Bool)
    /// Settings › Payment methods.
    case paymentMethods
    /// Settings › Rules: categorization rules ("if it says Uber → Transport").
    case categorizationRules
    /// A credit card's detail, by its account.
    case creditCard(accountID: UUID)
    /// A bank account and its one debit card, which share a screen.
    case bankAccount(accountID: UUID)
    /// A cash account's detail: rename, latest movements and delete.
    case cash(accountID: UUID)
    /// The movement list opened from an account, already filtered to it.
    case transactions(accountID: UUID? = nil)
    /// One movement's detail, with its actions (edit, receipt, split, delete).
    case transaction(id: UUID)
    /// Recurring movements and subscriptions.
    case recurring
    /// A recurring rule's editor; `nil` creates one.
    case recurringRule(id: UUID?)
    /// Savings goals, reached from home.
    case goals
    /// Loans and personal debts, reached from home.
    case debts
    /// What needs attention now, reached from the bell on home.
    case notifications
}

/// Single owner of the navigation stack. Feature views don't see it: they expose navigation as
/// closures, and `RootView` translates them into router calls.
@MainActor
@Observable
public final class AppRouter {
    public var path = NavigationPath()

    public init() {}

    public func push(_ route: AppRoute) {
        path.append(route)
    }

    public func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }
}
