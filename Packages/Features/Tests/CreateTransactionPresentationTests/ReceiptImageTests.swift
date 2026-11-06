import CreateTransactionDomain
import DomainSamples
import FeatureTestSupport
import Foundation
import Testing
@testable import CreateTransactionPresentation

final class ReceiptSaverSpy: ReceiptImageSaving, @unchecked Sendable {
    private let outcome: ReceiptImageSaveOutcome
    private(set) var saved: [Data] = []

    init(_ outcome: ReceiptImageSaveOutcome) {
        self.outcome = outcome
    }

    func save(pngData: Data) async -> ReceiptImageSaveOutcome {
        saved.append(pngData)
        return outcome
    }
}

@Suite("Receipt image")
@MainActor
struct ReceiptImageTests {
    private let png = Data([0x89, 0x50, 0x4E, 0x47])

    private func savedReceipt(saver: ReceiptSaverSpy?) async -> CreateTransactionViewModel {
        let viewModel = CreateTransactionFactory.make(receiptSaver: saver)
        await viewModel.load()
        for key in [8, 7, 9] {
            viewModel.press(.digit(key))
        }
        viewModel.selectCategory("restaurants")
        viewModel.selectSource(.card(SampleData.IDs.savingsDebit))
        viewModel.description = "Chicken (delivery)"
        viewModel.debitedText = "24.28"
        await viewModel.save()
        return viewModel
    }

    @Test
    func savingHandsThePNGToPhotosAndMarksItSaved() async {
        let saver = ReceiptSaverSpy(.saved)
        let viewModel = await savedReceipt(saver: saver)

        await viewModel.saveReceiptImage(png)

        #expect(saver.saved == [png])
        #expect(viewModel.receiptImageStatus == .saved)
        viewModel.dismissReceiptImageMessage()
        #expect(viewModel.receiptImageStatus == .saved)
    }

    @Test
    func deniedAccessAsksForSettingsAndCanBeDismissed() async {
        let viewModel = await savedReceipt(saver: ReceiptSaverSpy(.denied))

        await viewModel.saveReceiptImage(png)
        #expect(viewModel.receiptImageStatus == .denied)

        viewModel.dismissReceiptImageMessage()
        #expect(viewModel.receiptImageStatus == .idle)
    }

    @Test
    func aFailedSaveShowsTheError() async {
        let viewModel = await savedReceipt(saver: ReceiptSaverSpy(.failed))

        await viewModel.saveReceiptImage(png)

        #expect(viewModel.receiptImageStatus == .failed)
    }

    @Test
    func aMissingImageFailsWithoutAskingForPhotos() async {
        let saver = ReceiptSaverSpy(.saved)
        let viewModel = await savedReceipt(saver: saver)

        await viewModel.saveReceiptImage(nil)

        #expect(saver.saved.isEmpty)
        #expect(viewModel.receiptImageStatus == .failed)
    }

    @Test
    func withoutASaverOnlySharingIsOffered() async {
        let viewModel = await savedReceipt(saver: nil)

        #expect(!viewModel.canSaveReceiptImage)
        await viewModel.saveReceiptImage(png)
        #expect(viewModel.receiptImageStatus == .idle)
    }

    @Test
    func loggingAnotherForgetsTheSavedState() async {
        let viewModel = await savedReceipt(saver: ReceiptSaverSpy(.saved))
        await viewModel.saveReceiptImage(png)

        await viewModel.startOver()

        #expect(viewModel.receiptImageStatus == .idle)
    }

    @Test
    func rendersAt3x() async throws {
        let viewModel = await savedReceipt(saver: nil)
        let saved = try #require(viewModel.saved)

        let image = try #require(ReceiptImageRenderer.image(of: viewModel, saved: saved))

        #expect(image.scale == 3)
        #expect(image.size.width == ReceiptImageRenderer.width)
    }
}
