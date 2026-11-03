import AccountsPresentation
import AddCardPresentation
import Core
import CreateTransactionPresentation
import CreditCardPresentation
import DesignSystem
import Domain
import HomePresentation
import LockPresentation
import OnboardingPresentation
import SettingsDomain
import SettingsPresentation
import SummaryPresentation
import SwiftUI
import TransactionsPresentation
import UniformTypeIdentifiers

/// Decides between onboarding and the main app, maps `AppRoute` to screens and owns the app lock.
/// Feature views only receive closures, so they never depend on the router or on each other.
struct RootView: View {
    private enum Phase {
        case loading
        case onboarding(OnboardingViewModel)
        case main
    }

    private let container: AppContainer
    private let notifications: NotificationResponder
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase = Phase.loading
    @State private var router = AppRouter()
    @State private var tab = MainTab.home
    @State private var screens: MainScreens?
    @State private var addCard: PresentedFlow<AddCardViewModel>?
    @State private var newMovement: PresentedFlow<CreateTransactionViewModel>?
    @State private var lock = LockState()
    /// A CSV picked during onboarding; it's imported once onboarding has saved the accounts.
    @State private var pendingImport: String?
    @State private var isPickingImport = false
    @State private var banner: String?
    @State private var coverWindow = CoverWindow()

    init(container: AppContainer, notifications: NotificationResponder) {
        self.container = container
        self.notifications = notifications
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                // The splash stays while settings load, so launch never flashes black.
                SplashView()
            case let .onboarding(viewModel):
                OnboardingFlowView(viewModel: viewModel, onImportCSV: { isPickingImport = true }, onFinish: finishOnboarding)
            case .main:
                main
            }
        }
        .onChange(of: cover, initial: true) { _, cover in showCover(cover) }
        .overlay(alignment: .top) {
            if let banner {
                Text(banner)
                    .font(KWTextStyle.label.font)
                    .foregroundStyle(KWColor.Text.onPositive)
                    .padding(.horizontal, KWSpacing.md)
                    .padding(.vertical, 10)
                    .background(KWColor.State.positive, in: Capsule())
                    .padding(.top, KWSpacing.xs)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(3))
                        self.banner = nil
                    }
            }
        }
        .fileImporter(isPresented: $isPickingImport, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            guard case let .success(url) = result else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            pendingImport = (try? Data(contentsOf: url)).flatMap { String(data: $0, encoding: .utf8) }
        }
        .animation(.snappy, value: banner)
        .task {
            notifications.handler = handleNotification
            await load()
        }
        .onOpenURL(perform: open)
        .onChange(of: screens?.home.overview) { _, overview in
            guard overview != nil, let home = screens?.home else { return }
            Task { await container.publish(from: home) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task { await sceneChanged(to: newPhase) }
        }
    }

    // MARK: - Main

    private var main: some View {
        NavigationStack(path: $router.path) {
            MainTabView(selection: $tab) { tab in
                if let screens {
                    tabContent(tab, screens: screens)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AppRoute.self, destination: destination)
        }
        .onChange(of: router.path.count) { oldCount, newCount in
            // Pushed screens edit cards and settings that the tabs summarize.
            if newCount < oldCount {
                reloadScreens()
            }
        }
        .fullScreenCover(item: $addCard, onDismiss: reloadScreens) { flow in
            AddCardFlowView(viewModel: flow.viewModel, onExit: exitAddCard)
        }
        .fullScreenCover(item: $newMovement, onDismiss: reloadScreens) { flow in
            CreateTransactionFlowView(viewModel: flow.viewModel) { newMovement = nil }
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: MainTab, screens: MainScreens) -> some View {
        switch tab {
        case .home:
            HomeView(viewModel: screens.home, actions: homeActions(screens))
        case .transactions:
            TransactionsView(viewModel: screens.transactions) { presentNewMovement() }
        case .accounts:
            AccountsView(
                viewModel: screens.accounts,
                onAdd: { presentAddCard() },
                onOpenCreditCard: { router.push(.creditCard(accountID: $0)) },
                onLinkCard: { presentAddCard(linkingTo: $0) },
            )
        case .summary:
            SummaryView(viewModel: screens.summary) { presentNewMovement() }
        }
    }

    private func homeActions(_ screens: MainScreens) -> HomeView.Actions {
        HomeView.Actions(
            search: {
                screens.transactions.filter = .all
                screens.transactions.wantsSearchFocus = true
                tab = .transactions
            },
            summary: { tab = .summary },
            settings: { router.push(.settings) },
            accounts: { tab = .accounts },
            newMovement: { presentNewMovement($0) },
            payCard: {
                // With a single card there's nothing to choose; otherwise the flow asks which one.
                let cards = screens.home.overview?.accounts.filter { $0.kind == .credit } ?? []
                presentNewMovement(.transfer, payingCard: cards.count == 1 ? cards.first?.id : nil)
            },
            allPlanned: {
                screens.transactions.query = ""
                screens.transactions.filter = .planned
                tab = .transactions
            },
            additionalCard: { router.push(.additionalCard(accountID: $0, cardID: $1)) },
        )
    }

    @ViewBuilder
    private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .settings:
            SettingsRoute(container: container, onBack: settingsClosed, onErased: returnToOnboarding)
        case let .creditCard(accountID, addsAdditional):
            CreditCardRoute(
                container: container,
                accountID: accountID,
                addsAdditional: addsAdditional,
                onBack: router.pop,
                onPay: { presentNewMovement(.transfer, payingCard: accountID) },
                onOpenAdditional: { router.push(.additionalCard(accountID: accountID, cardID: $0)) },
            )
        case let .additionalCard(accountID, cardID):
            AdditionalCardRoute(container: container, accountID: accountID, cardID: cardID, onBack: router.pop)
        }
    }

    // MARK: - Flows

    private func presentNewMovement(
        _ kind: TransactionKind = .expense,
        payingCard cardAccountID: UUID? = nil,
        category categoryID: String? = nil,
    ) {
        let viewModel = container.makeCreateTransactionViewModel(kind: kind)
        if let cardAccountID {
            viewModel.presetTransfer(to: cardAccountID)
        }
        if let categoryID {
            viewModel.presetCategory(categoryID)
        }
        newMovement = PresentedFlow(viewModel: viewModel)
    }

    private func presentAddCard(linkingTo accountID: UUID? = nil) {
        let viewModel = container.makeAddCardViewModel()
        if let accountID {
            viewModel.choose(.debit, linkingTo: accountID)
        }
        addCard = PresentedFlow(viewModel: viewModel)
    }

    private func exitAddCard(_ exit: AddCardViewModel.Exit) {
        addCard = nil
        switch exit {
        case .close:
            break
        case let .viewCreditCard(accountID):
            router.push(.creditCard(accountID: accountID))
        case let .addAdditional(accountID):
            router.push(.creditCard(accountID: accountID, addsAdditional: true))
        }
    }

    private func reloadScreens() {
        Task { await screens?.reload() }
    }

    private func settingsClosed() {
        router.pop()
        Task { await refreshLockSettings() }
    }

    // MARK: - Phases

    private func load() async {
        guard case .loading = phase else { return }
        let settings = try? await container.makeGetSettings().execute()
        if settings?.hasCompletedOnboarding == true {
            enterMain()
            lock.settings = settings
            lock.isLocked = lock.appliesOnLaunch
            openQuickLogRequest()
        } else {
            phase = .onboarding(container.makeOnboardingViewModel())
        }
        #if DEBUG
        if AppEnvironment.current.opensNewMovement, case .main = phase {
            presentNewMovement()
        }
        #endif
    }

    private func enterMain() {
        screens = MainScreens(container: container)
        tab = .home
        phase = .main
    }

    private func finishOnboarding(_ exit: OnboardingFlowView.Exit) {
        enterMain()
        Task { await refreshLockSettings() }
        if let csv = pendingImport {
            pendingImport = nil
            Task { await importAfterOnboarding(csv) }
        }
        if exit == .logFirstExpense {
            presentNewMovement()
        }
    }

    private func importAfterOnboarding(_ csv: String) async {
        guard let summary = try? await container.makeImportTransactions().execute(csv: csv) else { return }
        banner = SettingsViewModel.importMessage(summary)
        await screens?.reload()
    }

    /// After "Delete all my data" there's nothing left to show, so the app starts over.
    private func returnToOnboarding() {
        Task { await container.clearOutside() }
        router.path = NavigationPath()
        screens = nil
        lock = LockState()
        phase = .onboarding(container.makeOnboardingViewModel())
    }
}

extension RootView {
    // MARK: - Outside the app

    /// Widget links: `keepwell://new-expense?category=…` opens a new expense in that category.
    private func open(_ url: URL) {
        guard case .main = phase, let link = AppLink.newExpenseCategory(from: url) else { return }
        router.path = NavigationPath()
        presentNewMovement(.expense, category: link)
    }

    /// A quick-log widget button ran while the app was away; open what it asked for.
    /// A quick-log widget button ran while the app was away. The tap is an explicit request, so it
    /// replaces a flow left open.
    private func openQuickLogRequest() {
        guard case .main = phase, let request = container.widgetSnapshots.takeQuickLogRequest() else { return }
        router.path = NavigationPath()
        addCard = nil
        presentNewMovement(.expense, category: request)
    }

    private func handleNotification(_ action: NotificationResponder.Action) async {
        switch action {
        case let .confirm(id):
            try? await DefaultConfirmPlannedTransactionUseCase(transactions: container.store).execute(id: id)
            await screens?.reload()
        case let .postpone(content, identifier):
            await container.reminders.postpone(content, identifier: identifier)
        }
    }

    // MARK: - Lock

    private enum Cover: Equatable {
        case hidden
        case lock
        /// Hides amounts from the app-switcher snapshot.
        case privacy
    }

    private var cover: Cover {
        guard case .main = phase else { return .hidden }
        if lock.isLocked {
            return .lock
        }
        return lock.hidesAmounts && scenePhase != .active ? .privacy : .hidden
    }

    private func showCover(_ cover: Cover) {
        switch cover {
        case .hidden:
            coverWindow.hide()
        case .lock:
            coverWindow.show(LockView(
                authenticator: container.authenticator,
                prefersPasscode: lock.settings?.unlockMethod == .passcode,
                showsHiddenAmountsNote: lock.settings?.hidesAmountsInAppSwitcher == true,
            ) { lock.isLocked = false })
        case .privacy:
            coverWindow.show(PrivacyCoverView())
        }
    }

    private func refreshLockSettings() async {
        lock.settings = try? await container.makeGetSettings().execute()
    }

    private func sceneChanged(to newPhase: ScenePhase) async {
        guard case .main = phase else { return }
        switch newPhase {
        case .background:
            lock.backgroundedAt = .now
        case .active:
            openQuickLogRequest()
            await refreshLockSettings()
            if lock.shouldRelock(now: .now) {
                lock.isLocked = true
            }
            lock.backgroundedAt = nil
        default:
            break
        }
    }
}
