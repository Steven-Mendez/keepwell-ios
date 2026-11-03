import FeatureTestSupport
import SwiftUI
import Testing
@testable import OnboardingPresentation

@Suite("Currencies snapshots")
@MainActor
struct CurrenciesSnapshotTests {
    @Test
    func nioSelectedWithDefaultRate() {
        assertScreenSnapshot(of: CurrenciesView(viewModel: OnboardingFactory.make()) {})
    }

    @Test
    func singleCurrencyHidesTheRate() {
        let viewModel = OnboardingFactory.make()
        viewModel.selectSecond(nil)
        assertScreenSnapshot(of: CurrenciesView(viewModel: viewModel) {})
    }
}
