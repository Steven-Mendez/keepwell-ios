import FeatureTestSupport
import SwiftUI
import Testing
@testable import OnboardingPresentation

@Suite("Currencies snapshots")
@MainActor
struct CurrenciesSnapshotTests {
    @Test
    func oneCurrencyByDefault() {
        assertScreenSnapshot(of: CurrenciesView(viewModel: OnboardingFactory.make()) {})
    }

    @Test
    func twoCurrenciesShowTheSwapAndTheRate() {
        assertScreenSnapshot(of: CurrenciesView(viewModel: OnboardingFactory.usdAndNIO(rate: "36.6243")) {})
    }
}
