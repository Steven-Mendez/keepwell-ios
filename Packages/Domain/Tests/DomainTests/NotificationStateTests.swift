import Foundation
import Testing
@testable import Domain

/// What a person can do to a notification, and how its id's day is read back for pruning. The
/// expectations mirror keepwell-web's `tests/notifications.test.ts`.
@Suite("Notification state")
struct NotificationStateTests {
    private let calendar = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func readingKeepsTheFirstTimeItWasRead() {
        let first = NotificationState(id: "price:x").applying(.markRead, at: now)
        let again = first.applying(.markRead, at: now.addingTimeInterval(60))
        #expect(again.readAt == now)
        #expect(again == first)
    }

    @Test
    func unreadClearsOnlyTheReadTime() {
        let deleted = NotificationState(id: "price:x").applying(.dismiss, at: now)
        let unread = deleted.applying(.markUnread, at: now)
        #expect(unread.readAt == nil)
        #expect(unread.isDismissed)
    }

    @Test
    func deletingAlsoReadsAndUndoingBringsItBackRead() {
        let deleted = NotificationState(id: "price:x").applying(.dismiss, at: now)
        #expect(deleted.isRead)
        #expect(deleted.isDismissed)
        let restored = deleted.applying(.restore, at: now)
        #expect(!restored.isDismissed)
        #expect(restored.isRead)
    }

    @Test
    func deletingKeepsAnEarlierReadTime() {
        let earlier = now.addingTimeInterval(-3600)
        let state = NotificationState(id: "price:x", readAt: earlier).applying(.dismiss, at: now)
        #expect(state.readAt == earlier)
        #expect(state.dismissedAt == now)
    }

    @Test
    func theDayComesBackFromAnId() {
        #expect(NotificationState.day(ofID: "payment:x:2026-11-15", calendar: calendar) == calendar.date(from: DateComponents(
            year: 2026,
            month: 11,
            day: 15,
        )))
        #expect(NotificationState.day(ofID: "expiry:x:2026-11", calendar: calendar) == calendar.date(from: DateComponents(
            year: 2026,
            month: 11,
            day: 1,
        )))
        #expect(NotificationState.day(ofID: "budget:groceries:2026-11:near", calendar: calendar) == calendar.date(from: DateComponents(
            year: 2026,
            month: 11,
            day: 1,
        )))
        #expect(NotificationState.day(ofID: "installment:x:3", calendar: calendar) == nil)
        #expect(NotificationState.day(ofID: "planned:00000000-0000-0000-0000-00000000a005", calendar: calendar) == nil)
    }

    @Test
    func idsOlderThanNinetyDaysAreStale() throws {
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 20)))
        #expect(NotificationState.isStale(id: "payment:a:2026-01-15", now: today, calendar: calendar))
        #expect(!NotificationState.isStale(id: "payment:a:2026-11-15", now: today, calendar: calendar))
        #expect(!NotificationState.isStale(id: "price:x", now: today, calendar: calendar))
    }
}
