import Domain
import Foundation
import HomeDomain

/// A delete that can still be taken back.
public struct UndoOffer: Equatable, Identifiable {
    public let id = UUID()
    public let ids: [String]
}

/// What the person does with notifications: open, read, unread and delete, each one a synced write
/// to the notification's state.
extension HomeViewModel {
    /// Whether reading and deleting is wired (it isn't in previews).
    public var canChangeNotifications: Bool {
        changeNotifications != nil
    }

    /// Opening a row reads it.
    public func open(_ item: InboxItem) async {
        guard !item.isRead else { return }
        await write(.markRead, [item.id])
    }

    public func toggleRead(_ item: InboxItem) async {
        await write(item.isRead ? .markUnread : .markRead, [item.id])
    }

    /// Deletes it and offers to take that back.
    public func delete(_ item: InboxItem) async {
        await write(.dismiss, [item.id])
        undoOffer = UndoOffer(ids: [item.id])
    }

    public func undo(_ offer: UndoOffer) async {
        undoOffer = nil
        await write(.restore, offer.ids)
    }

    public func clearUndoOffer() {
        undoOffer = nil
    }

    public func markAllRead(now: Date = .now) async {
        await write(.markRead, inbox(now: now, calendar: calendar).filter { !$0.isRead }.map(\.id))
    }

    /// Proposals stay: they wait for an answer, not for being read.
    public func deleteRead(now: Date = .now) async {
        let ids = inbox(now: now, calendar: calendar).filter { $0.isRead && $0.kind != .proposal }.map(\.id)
        guard !ids.isEmpty else { return }
        await write(.dismiss, ids)
        undoOffer = UndoOffer(ids: ids)
    }

    /// A notification the system showed was opened.
    public func markRead(notificationID: String) async {
        await write(.markRead, [notificationID])
    }

    /// Ids the system must not show any more: read or deleted on this iPhone or another.
    public var settledNotificationIDs: [String] {
        notificationStates.values.filter { $0.isRead || $0.isDismissed }.map(\.id)
    }

    private func write(_ change: NotificationState.Change, _ ids: [String]) async {
        guard let changeNotifications, !ids.isEmpty else { return }
        do {
            try await changeNotifications.execute(change, ids: ids)
        } catch {
            actionError = String(localized: "We couldn't save the change. Try again.", bundle: #bundle)
        }
        await loadStates()
    }
}
