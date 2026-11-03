import FeatureTestSupport
import SwiftUI
import Testing
@testable import AddCardPresentation

@Suite("Plastic snapshots")
@MainActor
struct PlasticSnapshotTests {
    private func creditViewModel() async -> AddCardViewModel {
        let viewModel = await AddCardFactory.loaded()
        viewModel.choose(.credit)
        viewModel.bank = "Banco Uno"
        viewModel.lastFour = "4321"
        return viewModel
    }

    @Test
    func plastic() async {
        await assertScreenSnapshot(of: PlasticView(viewModel: creditViewModel()) {})
    }

    @Test
    func debitPlasticPicksTheAccount() async {
        let viewModel = await AddCardFactory.loaded()
        viewModel.choose(.debit)
        assertScreenSnapshot(of: PlasticView(viewModel: viewModel) {})
    }
}
