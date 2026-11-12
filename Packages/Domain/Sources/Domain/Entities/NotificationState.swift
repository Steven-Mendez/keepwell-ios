import Foundation

/// What the person did with one notification. Notifications themselves are derived from the ledger
/// and never stored; this is the only thing kept, keyed by the notification's id (ADR 0012 in
/// keepwell-api). Absent means unread and in the inbox.
public struct NotificationState: Hashable, Sendable, Identifiable {
    public let id: String
    public var readAt: Date?
    public var dismissedAt: Date?

    public init(id: String, readAt: Date? = nil, dismissedAt: Date? = nil) {
        self.id = id
        self.readAt = readAt
        self.dismissedAt = dismissedAt
    }

    public var isRead: Bool {
        readAt != nil
    }

    public var isDismissed: Bool {
        dismissedAt != nil
    }

    /// What a person can do to a notification.
    public enum Change: Sendable {
        /// Keeps the first time it was read, so "read 3 days ago" doesn't move on every open.
        case markRead
        case markUnread
        /// Deleting also reads it: undoing the delete brings it back without the unread dot.
        case dismiss
        case restore
    }

    /// The state after `change`; shared by every store so they agree on the semantics.
    public func applying(_ change: Change, at now: Date) -> Self {
        var next = self
        switch change {
        case .markRead:
            next.readAt = readAt ?? now
        case .markUnread:
            next.readAt = nil
        case .dismiss:
            next.dismissedAt = now
            next.readAt = readAt ?? now
        case .restore:
            next.dismissedAt = nil
        }
        return next
    }

    /// Days after its day that a notification's state is kept before it is tombstoned.
    public static let retentionDays = 90

    /// The calendar day an id carries (`payment:<account>:2026-11-15`, `expiry:<card>:2026-11`),
    /// for pruning state nobody will see again. `nil` for ids with no day (installments, price
    /// increases, drafts, proposals): those go once the thing they point at is gone.
    public static func day(ofID id: String, calendar: Calendar = .current) -> Date? {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        for part in parts.dropFirst() {
            let pieces = part.split(separator: "-", omittingEmptySubsequences: false)
            guard (2 ... 3).contains(pieces.count), pieces[0].count == 4, pieces[1].count == 2,
                  pieces.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
                  let year = Int(pieces[0]), let month = Int(pieces[1]),
                  pieces.count == 2 || pieces[2].count == 2
            else { continue }
            let day = pieces.count == 3 ? Int(pieces[2]) ?? 1 : 1
            return calendar.date(from: DateComponents(year: year, month: month, day: day))
        }
        return nil
    }

    /// Ids whose day is more than `retentionDays` before `now`.
    public static func isStale(id: String, now: Date, calendar: Calendar = .current) -> Bool {
        guard let day = day(ofID: id, calendar: calendar),
              let limit = calendar.date(byAdding: .day, value: -retentionDays, to: now)
        else { return false }
        return day < limit
    }
}
