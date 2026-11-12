import Domain
import Foundation
import Observation

/// "Undo" for what was just done to a movement, shown as a toast over every screen, so it survives
/// the detail closing after a delete. One offer at a time: a newer one replaces it (the older
/// deletion still happens when its own window runs out).
@MainActor
@Observable
public final class MovementUndo {
    public struct Offer: Identifiable, Equatable {
        public enum Action: Equatable {
            case delete(UUID)
            /// Back to a draft on the date it was planned for.
            case confirm(UUID, plannedDate: Date)
        }

        public let id = UUID()
        public let message: String
        public let action: Action
    }

    /// How long the toast stays: as long as a deletion can be undone.
    public static let window = DeferredTransactionDeletions.undoWindow

    public private(set) var offer: Offer?

    private let undoDelete: any UndoDeleteTransactionUseCase
    private let unconfirm: any UnconfirmTransactionUseCase
    /// Run after an undo, so the screens read the movement again; set by the root view.
    public var onUndone: @MainActor () async -> Void = {}

    public init(undoDelete: any UndoDeleteTransactionUseCase, unconfirm: any UnconfirmTransactionUseCase) {
        self.undoDelete = undoDelete
        self.unconfirm = unconfirm
    }

    /// The toast's button.
    public static var actionTitle: String {
        String(localized: "Undo", bundle: #bundle)
    }

    public func offerDeleted(_ transaction: Transaction) {
        offer = Offer(message: String(localized: "Transaction deleted", bundle: #bundle), action: .delete(transaction.id))
    }

    /// `planned` as it was before confirming, for its date.
    public func offerConfirmed(_ planned: Transaction) {
        offer = Offer(
            message: String(localized: "Confirmed", bundle: #bundle),
            action: .confirm(planned.id, plannedDate: planned.date),
        )
    }

    public func undo(_ offer: Offer) async {
        if self.offer == offer {
            self.offer = nil
        }
        switch offer.action {
        case let .delete(id):
            _ = await undoDelete.execute(id: id)
        case let .confirm(id, plannedDate):
            // Only fails when the movement is gone (deleted elsewhere): then there is nothing to take back.
            try? await unconfirm.execute(id: id, plannedDate: plannedDate)
        }
        await onUndone()
    }

    /// The toast ran out (or the screen went away).
    public func dismiss(_ offer: Offer) {
        if self.offer == offer {
            self.offer = nil
        }
    }
}
