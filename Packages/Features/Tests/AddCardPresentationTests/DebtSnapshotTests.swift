import FeatureTestSupport
import SwiftUI
import Testing
@testable import AddCardPresentation

@Suite("Debt snapshots")
@MainActor
struct DebtSnapshotTests {
    private func creditViewModel() async -> AddCardViewModel {
        let viewModel = await AddCardFactory.loaded()
        viewModel.choose(.credit)
        viewModel.bank = "Bank One"
        viewModel.lastFour = "4321"
        return viewModel
    }

    @Test
    func debt() async {
        await assertScreenSnapshot(of: DebtView(viewModel: creditViewModel()) {})
    }
}
