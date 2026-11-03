import DomainSamples
import FeatureTestSupport
import SwiftUI
import Testing
@testable import CreateTransactionPresentation

@Suite("Category snapshots")
@MainActor
struct CategorySnapshotTests {
    private func filled() async -> CreateTransactionViewModel {
        let viewModel = await CreateTransactionFactory.loaded()
        for key in [8, 7, 9] {
            viewModel.press(.digit(key))
        }
        return viewModel
    }

    @Test
    func category() async {
        let viewModel = await filled()
        viewModel.selectCategory("restaurants")
        viewModel.path = [.category]
        assertScreenSnapshot(of: CategoryView(viewModel: viewModel) {})
    }
}
