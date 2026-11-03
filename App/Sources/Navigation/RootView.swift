import AccountsPresentation
import AddCardPresentation
import Core
import CreateTransactionPresentation
import DesignSystem
import OnboardingPresentation
import SwiftUI

/// Decides between onboarding and the main app, and maps `AppRoute` to screens. Feature views
/// only receive closures, so they never depend on the router or on each other.
struct RootView: View {
    private enum Phase {
        case loading
        case onboarding(OnboardingViewModel)
        case main
    }

    private let container: AppContainer
    @State private var phase = Phase.loading
    @State private var router = AppRouter()
    @State private var tab = MainTab.home
    @State private var accounts: AccountsViewModel?
    @State private var addCard: PresentedFlow<AddCardViewModel>?
    @State private var newMovement: PresentedFlow<CreateTransactionViewModel>?
    @State private var hasMovements = false

    init(container: AppContainer) {
        self.container = container
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                KWColor.Surface.bg.ignoresSafeArea()
            case let .onboarding(viewModel):
                OnboardingFlowView(viewModel: viewModel, onImportCSV: {}, onFinish: finishOnboarding)
            case .main:
                main
            }
        }
        .task { await load() }
    }

    private var main: some View {
        NavigationStack(path: $router.path) {
            MainTabView(selection: $tab) { tab in
                switch tab {
                case .accounts:
                    if let accounts {
                        AccountsView(
                            viewModel: accounts,
                            onAdd: { presentAddCard() },
                            onOpenCreditCard: { _ in },
                            onLinkCard: { presentAddCard(linkingTo: $0) },
                        )
                    }
                case .home, .transactions, .summary:
                    PendingTabView(tab: tab, hasMovements: hasMovements, onNewMovement: presentNewMovement)
                        .task { hasMovements = await container.hasMovements() }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AppRoute.self) { _ in EmptyView() }
        }
        .fullScreenCover(item: $addCard, onDismiss: reloadAccounts) { flow in
            AddCardFlowView(viewModel: flow.viewModel) { _ in addCard = nil }
        }
        .fullScreenCover(item: $newMovement, onDismiss: reloadAccounts) { flow in
            CreateTransactionFlowView(viewModel: flow.viewModel) { newMovement = nil }
        }
    }

    private func presentNewMovement() {
        newMovement = PresentedFlow(viewModel: container.makeCreateTransactionViewModel())
    }

    private func presentAddCard(linkingTo accountID: UUID? = nil) {
        let viewModel = container.makeAddCardViewModel()
        if let accountID {
            viewModel.choose(.debit, linkingTo: accountID)
        }
        addCard = PresentedFlow(viewModel: viewModel)
    }

    private func reloadAccounts() {
        Task {
            await accounts?.load()
            hasMovements = await container.hasMovements()
        }
    }

    private func load() async {
        guard case .loading = phase else { return }
        let settings = try? await container.makeGetSettings().execute()
        accounts = container.makeAccountsViewModel()
        phase = settings?.hasCompletedOnboarding == true ? .main : .onboarding(container.makeOnboardingViewModel())
        #if DEBUG
        if AppEnvironment.current.opensNewMovement, case .main = phase {
            presentNewMovement()
        }
        #endif
    }

    private func finishOnboarding(_ exit: OnboardingFlowView.Exit) {
        phase = .main
        if exit == .logFirstExpense {
            presentNewMovement()
        }
    }
}

/// Wraps a flow's view model so it can drive `fullScreenCover(item:)`.
struct PresentedFlow<ViewModel>: Identifiable {
    let id = UUID()
    let viewModel: ViewModel
}
