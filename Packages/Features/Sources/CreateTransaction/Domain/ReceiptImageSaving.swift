import Foundation

/// How saving a receipt image to the photo library ended. A result rather than a thrown error
/// because "denied" is an expected answer from the person, not a failure of the app.
public enum ReceiptImageSaveOutcome: Equatable, Sendable {
    case saved
    /// The person refused, or restricted, adding photos; only Settings can change that now.
    case denied
    case failed
}

/// Adds a rendered receipt (PNG data) to the person's photo library. The app implements it with
/// Photos, asking for add-only access, so the receipt screen stays testable without it.
public protocol ReceiptImageSaving: Sendable {
    func save(pngData: Data) async -> ReceiptImageSaveOutcome
}
