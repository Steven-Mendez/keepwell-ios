import Observation
import SwiftUI

/// Every pushable destination. Cases carry identifiers, never models, so a path stays cheap to
/// store and can later be encoded for state restoration.
public enum AppRoute: Hashable, Sendable {
    case settings
    /// A credit card's detail, by its account.
    case creditCard(accountID: UUID, addsAdditional: Bool = false)
    /// The controls of one additional card on that account.
    case additionalCard(accountID: UUID, cardID: UUID)
    /// A debit card and the bank account it spends from.
    case debitCard(cardID: UUID)
    /// The movement list opened from an account or card, already filtered to it. A card wins
    /// over an account when both are given.
    case transactions(accountID: UUID? = nil, cardID: UUID? = nil)
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
