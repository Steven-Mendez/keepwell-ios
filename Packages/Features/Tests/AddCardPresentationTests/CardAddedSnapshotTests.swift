import FeatureTestSupport
import SwiftUI
import Testing
@testable import AddCardPresentation

@Suite("CardAdded snapshots")
@MainActor
struct CardAddedSnapshotTests {
    private func creditViewModel() async -> AddCardViewModel {
        let viewModel = await AddCardFactory.loaded()
        viewModel.choose(.credit)
        viewModel.bank = "Bank One"
        viewModel.lastFour = "4321"
        return viewModel
    }

    @Test
    func added() async {
        let viewModel = await creditViewModel()
        assertScreenSnapshot(of: CardAddedView(viewModel: viewModel, onViewCard: {}, onAddAnother: {}))
    }
}
