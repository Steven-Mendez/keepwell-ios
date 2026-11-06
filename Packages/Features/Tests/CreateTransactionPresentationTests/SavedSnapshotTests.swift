import DesignSystem
import DomainSamples
import FeatureTestSupport
import SwiftUI
import Testing
@testable import CreateTransactionPresentation

@Suite("Saved snapshots")
@MainActor
struct SavedSnapshotTests {
    private func filled() async -> CreateTransactionViewModel {
        let viewModel = CreateTransactionFactory.make(receiptSaver: ReceiptSaverSpy(.saved))
        await viewModel.load()
        for key in [8, 7, 9] {
            viewModel.press(.digit(key))
        }
        return viewModel
    }

    @Test
    func saved() async {
        let viewModel = await filled()
        viewModel.selectCategory("restaurants")
        viewModel.selectSource(.card(SampleData.IDs.savingsDebit))
        viewModel.description = "Chicken (delivery)"
        viewModel.debitedText = "24.28"
        await viewModel.save()
        assertScreenSnapshot(of: SavedView(viewModel: viewModel) {})
    }

    /// The picture "Save image" and "Share" send, as `ImageRenderer` draws it.
    @Test
    func receiptImage() async throws {
        let viewModel = await filled()
        viewModel.selectCategory("restaurants")
        viewModel.selectSource(.card(SampleData.IDs.savingsDebit))
        viewModel.description = "Chicken (delivery)"
        viewModel.debitedText = "24.28"
        await viewModel.save()
        KWFonts.register()
        let saved = try #require(viewModel.saved)
        let image = try #require(ReceiptImageRenderer.image(of: viewModel, saved: saved))
        assertRenderedImageSnapshot(of: image)
    }
}
