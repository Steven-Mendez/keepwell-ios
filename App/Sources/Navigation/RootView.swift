import Core
import DesignSystem
import SwiftUI

/// Maps `AppRoute` to screens. Feature views only receive closures, so they never depend on the
/// router or on each other.
struct RootView: View {
    private let container: AppContainer
    @State private var router = AppRouter()

    init(container: AppContainer) {
        self.container = container
    }

    var body: some View {
        NavigationStack(path: $router.path) {
            KWColor.Surface.bg
                .ignoresSafeArea()
                .accessibilityIdentifier("root")
                .navigationDestination(for: AppRoute.self) { _ in EmptyView() }
        }
    }
}
