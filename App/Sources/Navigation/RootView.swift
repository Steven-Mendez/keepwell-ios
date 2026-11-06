import AccountsPresentation
import AddCardPresentation
import Core
import CreateTransactionDomain
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
import SwiftData
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

    let container: AppContainer
    private let notifications: NotificationResponder
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase = Phase.loading
    @State private var router = AppRouter()
    /// For the route mapping in `RootView+Routes`; `AppRouter` is a reference, so pushes reach this stack.
    var navigator: AppRouter { router }
    @State private var tab = MainTab.home
    @State private var screens: MainScreens?
    @State private var addCard: PresentedFlow<AddCardViewModel>?
    @State private var newMovement: PresentedFlow<CreateTransactionViewModel>?
    @State private var movementMenu: PresentedFlow<NewMovementMenuViewModel>?
    /// Chosen in the menu sheet; the flow opens once the sheet has finished closing.
    @State private var chosenMovement: MovementType?
    @State private var lock = LockState()
    /// A CSV picked during onboarding; it's imported once onboarding has saved the accounts.
    @State private var pendingImport: String?
    @State private var isPickingImport = false
    @State private var isPickingBackup = false
    @State private var banner: String?
    @State private var coverWindow = CoverWindow()
    /// Bumped on every store save so home, and with it the widgets, reload.
    @State private var storeRevision = 0

    init(container: AppContainer, notifications: NotificationResponder) {
        self.container = container
        self.notifications = notifications
    }

    var body: some View {
        phaseContent
            .onChange(of: cover, initial: true) { _, cover in showCover(cover) }
            .overlay(alignment: .top) { bannerView }
            .fileImporter(
                isPresented: $isPickingImport,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                onCompletion: readPickedCSV,
            )
            .background {
                // A second importer can't share a view with the first, so it lives on the background.
                Color.clear.fileImporter(isPresented: $isPickingBackup, allowedContentTypes: [.json]) { result in
                    guard case let .success(url) = result else { return }
                    Task { await restoreFromFile(url) }
                }
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
            // Any write (a movement logged, edited or deleted from any screen, an import, a widget
            // quick log) changes what home and the widgets show, even when home isn't on screen.
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)) { _ in
                storeRevision += 1
            }
            .task(id: storeRevision) {
                guard storeRevision > 0 else { return }
                // Saves come in bursts (a transfer writes both sides), so wait for the last one.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await screens?.home.load()
            }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .loading:
            // The splash stays while settings load, so launch never flashes black.
            SplashView()
        case let .onboarding(viewModel):
            OnboardingRoute(
                container: container,
                viewModel: viewModel,
                onImportCSV: { isPickingImport = true },
                onRestoreFile: { isPickingBackup = true },
                onFinish: finishOnboarding,
            )
        case .main:
            main
        }
    }

    @ViewBuilder
    private var bannerView: some View {
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

    /// Keeps the picked CSV's text for after onboarding saves the accounts it refers to.
    private func readPickedCSV(_ result: Result<URL, any Error>) {
        guard case let .success(url) = result else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        pendingImport = (try? Data(contentsOf: url)).flatMap { String(data: $0, encoding: .utf8) }
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
        .sheet(item: $movementMenu, onDismiss: openChosenMovement) { menu in
            NewMovementSheet(
                viewModel: menu.viewModel,
                onSelect: { type in
                    chosenMovement = type
                    movementMenu = nil
                },
                onClose: { movementMenu = nil },
            )
            .presentationDetents([.height(480), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(KWColor.Surface.bg)
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: MainTab, screens: MainScreens) -> some View {
        switch tab {
        case .home:
            HomeView(viewModel: screens.home, actions: homeActions(screens))
        case .transactions:
            TransactionsView(viewModel: screens.transactions) { presentMovementMenu() }
        case .accounts:
            AccountsView(
                viewModel: screens.accounts,
                onAdd: { presentAddCard() },
                onOpenCreditCard: { router.push(.creditCard(accountID: $0)) },
                onOpenBankAccount: { router.push(.bankAccount(accountID: $0)) },
                onOpenAccountMovements: { router.push(.transactions(accountID: $0)) },
            )
        case .summary:
            SummaryView(viewModel: screens.summary) { presentMovementMenu() }
        }
    }

    private func homeActions(_ screens: MainScreens) -> HomeView.Actions {
        HomeView.Actions(
            search: {
                screens.transactions.filter = .all
                screens.transactions.scope = .all
                screens.transactions.wantsSearchFocus = true
                tab = .transactions
            },
            summary: { tab = .summary },
            settings: { router.push(.settings) },
            accounts: { tab = .accounts },
            newMovement: { presentNewMovement(MovementType($0)) },
            payCard: {
                // With a single card there's nothing to choose; otherwise the flow asks which one.
                let cards = screens.home.overview?.accounts.filter { $0.kind == .credit } ?? []
                presentNewMovement(.cardPayment, payingCard: cards.count == 1 ? cards.first?.id : nil)
            },
            allPlanned: {
                screens.transactions.query = ""
                screens.transactions.scope = .all
                screens.transactions.filter = .planned
                tab = .transactions
            },
            allTransactions: {
                screens.transactions.query = ""
                screens.transactions.filter = .all
                tab = .transactions
            },
        )
    }
}

extension RootView {
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

    /// A Keepwell backup brings accounts, cards and movements at once and marks onboarding done.
    private func restoreFromFile(_ url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        let data = try? Data(contentsOf: url)
        if didAccess {
            url.stopAccessingSecurityScopedResource()
        }
        guard let data, let summary = try? await container.makeRestoreBackup().execute(data) else {
            banner = String(localized: "That file isn't a Keepwell backup.")
            return
        }
        finishOnboarding(.home)
        banner = String(localized: "Restored \(summary.accounts) accounts and \(summary.transactions) movements")
    }

    private func importAfterOnboarding(_ csv: String) async {
        guard let summary = try? await container.makeImportTransactions().execute(csv: csv) else { return }
        banner = SettingsViewModel.importMessage(summary)
        await screens?.reload()
    }

    /// After "Delete all my data" there's nothing left to show, so the app starts over.
    func returnToOnboarding() {
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
                viewModel: container.makeLockViewModel(prefersPasscode: lock.settings?.unlockMethod == .passcode),
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
            // Leaving the app is when the person looks at the home screen, so the widgets must
            // hold the latest state by then, including a month that turned while the app was open.
            if let home = screens?.home {
                await home.load()
                container.publishWidgets(from: home)
            }
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

extension RootView {
    // MARK: - Flows

    /// "What are you recording?", for entries that don't already say which kind.
    func presentMovementMenu() {
        movementMenu = PresentedFlow(viewModel: container.makeNewMovementMenuViewModel())
    }

    private func openChosenMovement() {
        guard let type = chosenMovement else { return }
        chosenMovement = nil
        presentNewMovement(type)
    }

    func presentNewMovement(
        _ type: MovementType = .expense,
        payingCard cardAccountID: UUID? = nil,
        category categoryID: String? = nil,
    ) {
        let viewModel = container.makeCreateTransactionViewModel(type: type)
        if let cardAccountID {
            viewModel.presetTransfer(to: cardAccountID)
        }
        if let categoryID {
            viewModel.presetCategory(categoryID)
        }
        newMovement = PresentedFlow(viewModel: viewModel)
    }

    func presentAddCard() {
        addCard = PresentedFlow(viewModel: container.makeAddCardViewModel())
    }

    private func exitAddCard(_ exit: AddCardViewModel.Exit) {
        addCard = nil
        switch exit {
        case .close:
            break
        case let .viewCreditCard(accountID):
            router.push(.creditCard(accountID: accountID))
        case let .viewBankAccount(accountID):
            router.push(.bankAccount(accountID: accountID))
        }
    }

    private func reloadScreens() {
        Task { await screens?.reload() }
    }

    func settingsClosed() {
        router.pop()
        Task { await refreshLockSettings() }
    }
}
