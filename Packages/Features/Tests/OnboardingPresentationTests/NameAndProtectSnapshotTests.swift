import FeatureTestSupport
import SwiftUI
import Testing
@testable import OnboardingPresentation

@Suite("Name and protect snapshots")
@MainActor
struct NameAndProtectSnapshotTests {
    @Test
    func nameEmpty() {
        assertScreenSnapshot(of: NameView(viewModel: OnboardingFactory.make()) {})
    }

    @Test
    func nameTyped() {
        let viewModel = OnboardingFactory.make()
        viewModel.nameText = "Steven"
        assertScreenSnapshot(of: NameView(viewModel: viewModel) {})
    }

    @Test
    func protectBeforeAPasscode() {
        assertScreenSnapshot(of: ProtectView(viewModel: OnboardingFactory.make(), onBack: {}, onSetUpPasscode: {}))
    }

    @Test
    func protectWithAPasscode() {
        let viewModel = OnboardingFactory.make()
        viewModel.passcodeCreated()
        assertScreenSnapshot(of: ProtectView(viewModel: viewModel, onBack: {}, onSetUpPasscode: {}))
    }
}
