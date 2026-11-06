import DomainSamples
import FeatureTestSupport
import SwiftUI
import Testing
@testable import CreateTransactionPresentation

@Suite("Method snapshots")
@MainActor
struct MethodSnapshotTests {
    private func filled() async -> CreateTransactionViewModel {
        let viewModel = await CreateTransactionFactory.loaded()
        for key in [8, 7, 9] {
            viewModel.press(.digit(key))
        }
        return viewModel
    }

    @Test
    func method() async {
        let viewModel = await filled()
        viewModel.selectCategory("restaurants")
        assertScreenSnapshot(of: MethodView(viewModel: viewModel) {})
    }
}
