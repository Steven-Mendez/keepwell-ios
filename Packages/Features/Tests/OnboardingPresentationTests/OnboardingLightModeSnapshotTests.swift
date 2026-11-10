import FeatureTestSupport
import SwiftUI
import Testing
@testable import OnboardingPresentation

/// Every onboarding step in light mode; the dark references are in the other suites.
@Suite("Onboarding light mode snapshots")
@MainActor
struct OnboardingLightModeSnapshotTests {
    @Test
    func splash() {
        assertScreenSnapshot(of: SplashView(), named: "light", colorScheme: .light)
    }

    @Test
    func welcome() {
        assertScreenSnapshot(of: WelcomeView(onStart: {}), named: "light", colorScheme: .light)
    }

    @Test
    func name() {
        let viewModel = OnboardingFactory.make()
        viewModel.nameText = "Steven"
        assertScreenSnapshot(of: NameView(viewModel: viewModel) {}, named: "light", colorScheme: .light)
    }

    @Test
    func currencies() {
        assertScreenSnapshot(
            of: CurrenciesView(viewModel: OnboardingFactory.usdAndNIO(rate: "36.6243")) {},
            named: "light",
            colorScheme: .light,
        )
    }

    @Test
    func accounts() {
        let viewModel = OnboardingFactory.usdAndNIO()
        viewModel.save(viewModel.newAccount(.bank))
        viewModel.save(viewModel.newAccount(.credit))
        assertScreenSnapshot(of: AccountsView(viewModel: viewModel, onBack: {}, onImportCSV: {}), named: "light", colorScheme: .light)
    }

    @Test
    func protect() {
        let viewModel = OnboardingFactory.make()
        viewModel.passcodeCreated()
        assertScreenSnapshot(of: ProtectView(viewModel: viewModel, onBack: {}, onSetUpPasscode: {}), named: "light", colorScheme: .light)
    }

    @Test
    func privacy() {
        assertScreenSnapshot(of: PrivacyView(viewModel: OnboardingFactory.make()) {}, named: "light", colorScheme: .light)
    }

    @Test
    func done() {
        let viewModel = OnboardingFactory.usdAndNIO(rate: "36.6243")
        viewModel.save(viewModel.newAccount(.bank))
        viewModel.nameText = "Steven"
        assertScreenSnapshot(
            of: DoneView(viewModel: viewModel, onLogFirstExpense: {}, onGoHome: {}),
            named: "light",
            colorScheme: .light,
        )
    }
}
