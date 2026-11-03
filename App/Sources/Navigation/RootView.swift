import Core
import SwiftUI
import TransactionsPresentation

/// Maps `AppRoute` to screens. Feature views only receive closures, so they never depend on the
/// router or on each other.
struct RootView: View {
    private let container: AppContainer
    @State private var router = AppRouter()
    @State private var dashboardViewModel: TransactionsViewModel

    init(container: AppContainer) {
        self.container = container
        _dashboardViewModel = State(initialValue: container.makeTransactionsViewModel())
    }

    var body: some View {
        NavigationStack(path: $router.path) {
            TransactionsDashboardView(
                viewModel: dashboardViewModel,
                formatter: container.currencyFormatter,
                onAddTransaction: { router.push(.addTransaction) },
            )
            .navigationDestination(for: AppRoute.self, destination: destination)
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .addTransaction:
            AddTransactionView(viewModel: container.makeAddTransactionViewModel()) {
                router.pop()
                Task { await dashboardViewModel.load() }
            }
        }
    }
}
