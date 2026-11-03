import Core
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
            MainTabView(selection: $tab) { _ in
                KWColor.Surface.bg
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AppRoute.self) { _ in EmptyView() }
        }
    }

    private func load() async {
        guard case .loading = phase else { return }
        let settings = try? await container.makeGetSettings().execute()
        phase = settings?.hasCompletedOnboarding == true ? .main : .onboarding(container.makeOnboardingViewModel())
    }

    private func finishOnboarding(_: OnboardingFlowView.Exit) {
        phase = .main
    }
}
