import CreateTransactionDomain
import Foundation
import Photos

/// Saves receipts with add-only access: Keepwell never needs to read the person's photos.
nonisolated struct PhotoLibraryReceiptSaver: ReceiptImageSaving {
    func save(pngData: Data) async -> ReceiptImageSaveOutcome {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .denied }
        do {
            try await PHPhotoLibrary.shared().performChanges(Self.addPhoto(pngData))
            return .saved
        } catch {
            return .failed
        }
    }

    /// Built outside any actor because Photos runs the change block on its own queue.
    private static func addPhoto(_ data: Data) -> @Sendable () -> Void {
        {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
        }
    }
}
