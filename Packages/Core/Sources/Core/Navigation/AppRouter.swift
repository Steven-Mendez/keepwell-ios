import Observation
import SwiftUI

/// Every pushable destination. Cases carry identifiers, never models, so a path stays cheap to
/// store and can later be encoded for state restoration.
public enum AppRoute: Hashable, Sendable {}

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
