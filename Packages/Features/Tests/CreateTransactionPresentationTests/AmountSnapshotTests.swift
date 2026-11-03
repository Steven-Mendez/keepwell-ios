import DomainSamples
import FeatureTestSupport
import SwiftUI
import Testing
@testable import CreateTransactionPresentation

@Suite("Amount snapshots")
@MainActor
struct AmountSnapshotTests {
    private func filled() async -> CreateTransactionViewModel {
        let viewModel = await CreateTransactionFactory.loaded()
        for key in [8, 7, 9] {
            viewModel.press(.digit(key))
        }
        return viewModel
    }

    @Test
    func amount() async {
        await assertScreenSnapshot(of: AmountView(viewModel: filled()) {})
    }
}
