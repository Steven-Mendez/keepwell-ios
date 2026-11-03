import Observation
import SwiftUI

/// Every pushable destination. Cases carry identifiers, never models, so a path stays cheap to
/// store and can later be encoded for state restoration.
public enum AppRoute: Hashable, Sendable {
    case settings
    /// Settings › Categories, opened on the income tab or the expense one.
    case categories(showsIncome: Bool)
    /// A credit card's detail, by its account.
    case creditCard(accountID: UUID, addsAdditional: Bool = false)
    /// The controls of one additional card on that account.
    case additionalCard(accountID: UUID, cardID: UUID)
    /// A bank account and its one debit card, which share a screen.
    case bankAccount(accountID: UUID)
    /// The movement list opened from an account, already filtered to it.
    case transactions(accountID: UUID? = nil)
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
