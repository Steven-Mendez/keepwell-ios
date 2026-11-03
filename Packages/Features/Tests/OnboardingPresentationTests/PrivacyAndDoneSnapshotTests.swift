import FeatureTestSupport
import SwiftUI
import Testing
@testable import OnboardingPresentation

@Suite("Privacy and done snapshots")
@MainActor
struct PrivacyAndDoneSnapshotTests {
    @Test
    func privacyWithEverythingOn() {
        assertScreenSnapshot(of: PrivacyView(viewModel: OnboardingFactory.make()) {})
    }

    @Test
    func doneSummarizesTheChoices() {
        let viewModel = OnboardingFactory.make()
        viewModel.useNicaraguaExample()
        viewModel.save(viewModel.newAccount(.bank))
        viewModel.save(viewModel.newAccount(.credit))
        viewModel.nameText = "Steven"
        assertScreenSnapshot(of: DoneView(viewModel: viewModel, onLogFirstExpense: {}, onGoHome: {}))
    }
}
