import CreateTransactionDomain
import Foundation

/// "Save image" on the receipt. The view renders the image (rendering needs SwiftUI) and hands
/// the PNG over, so the outcome handling here is testable with a fake saver.
extension CreateTransactionViewModel {
    public enum ReceiptImageStatus: Equatable, Sendable {
        case idle
        case saving
        case saved
        /// Photos access was refused: the receipt offers a way to Settings.
        case denied
        case failed
    }

    public var canSaveReceiptImage: Bool {
        receiptSaver != nil
    }

    public func saveReceiptImage(_ pngData: Data?) async {
        guard let receiptSaver, receiptImageStatus != .saving else { return }
        guard let pngData else {
            receiptImageStatus = .failed
            return
        }
        receiptImageStatus = .saving
        switch await receiptSaver.save(pngData: pngData) {
        case .saved: receiptImageStatus = .saved
        case .denied: receiptImageStatus = .denied
        case .failed: receiptImageStatus = .failed
        }
    }

    /// Closes the denied or failed message; a saved receipt keeps its "Saved" state.
    public func dismissReceiptImageMessage() {
        if receiptImageStatus == .denied || receiptImageStatus == .failed {
            receiptImageStatus = .idle
        }
    }
}
