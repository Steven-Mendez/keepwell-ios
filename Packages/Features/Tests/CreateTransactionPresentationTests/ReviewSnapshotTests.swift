import DomainSamples
import FeatureTestSupport
import SwiftUI
import Testing
@testable import CreateTransactionPresentation

@Suite("Review snapshots")
@MainActor
struct ReviewSnapshotTests {
    private func filled() async -> CreateTransactionViewModel {
        let viewModel = await CreateTransactionFactory.loaded()
        for key in [8, 7, 9] {
            viewModel.press(.digit(key))
        }
        return viewModel
    }

    @Test
    func review() async {
        let viewModel = await filled()
        viewModel.selectCategory("restaurants")
        viewModel.selectSource(.card(SampleData.IDs.savingsDebit))
        viewModel.description = "Pollo (a domicilio)"
        viewModel.debitedText = "24.28"
        assertScreenSnapshot(of: ReviewView(viewModel: viewModel) {})
    }
}
