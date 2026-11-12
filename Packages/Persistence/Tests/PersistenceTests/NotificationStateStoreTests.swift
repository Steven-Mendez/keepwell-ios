import Domain
import Foundation
import Testing
@testable import Persistence

/// Read and deleted notifications: same semantics as keepwell-web's `notificationStateRepository`,
/// every change an event in the outbox, and rows from the server applied without echoing back.
@Suite("Notification states")
struct NotificationStateStoreTests {
    private func store() throws -> SwiftDataStore {
        try SwiftDataStore(modelContainer: ModelContainerFactory.make(store: .inMemory))
    }

    private let id = "payment:00000000-0000-0000-0000-00000000a005:2026-11-15"

    @Test
    func readUnreadDeleteAndRestoreEachGoToTheOutbox() async throws {
        let store = try store()
        try await store.apply(.markRead, to: [id])
        #expect(try await store.fetchNotificationStates().first?.isRead == true)
        try await store.apply(.markUnread, to: [id])
        #expect(try await store.fetchNotificationStates().first?.isRead == false)
        try await store.apply(.dismiss, to: [id])
        #expect(try await store.fetchNotificationStates().first?.isDismissed == true)
        try await store.apply(.restore, to: [id])
        let restored = try #require(try await store.fetchNotificationStates().first)
        #expect(!restored.isDismissed)
        #expect(restored.isRead)

        let events = try await store.pendingEvents(limit: 50)
        #expect(events.map(\.entity) == Array(repeating: "notificationState", count: 4))
        #expect(events.map(\.operation) == ["create", "update", "update", "update"])
        #expect(events.allSatisfy { $0.entityID == id })
    }

    @Test
    func theWireRowHasExactlyTheContractColumns() async throws {
        let store = try store()
        try await store.apply(.dismiss, to: [id])
        let event = try #require(try await store.pendingEvents(limit: 5).first)
        let row = try #require(JSONSerialization.jsonObject(with: event.payload) as? [String: Any])
        #expect(Set(row.keys) == ["id", "read_at", "dismissed_at", "created_at", "updated_at", "deleted_at"])
        #expect(row["id"] as? String == id)
        #expect(row["read_at"] is String)
        #expect(row["dismissed_at"] is String)
        #expect(row["deleted_at"] is NSNull)
    }

    @Test
    func readingKeepsTheFirstReadTimeAndAChangeThatChangesNothingWritesNothing() async throws {
        let store = try store()
        try await store.apply(.markRead, to: ["price:x"])
        let first = try #require(try await store.fetchNotificationStates().first?.readAt)
        try await store.apply(.markRead, to: ["price:x"])
        #expect(try await store.fetchNotificationStates().first?.readAt == first)
        #expect(await store.pendingCount() == 1)
    }

    @Test
    func theSameIdTwiceInOneCallIsOneRow() async throws {
        let store = try store()
        try await store.apply(.markRead, to: ["price:x", "price:x"])
        #expect(await store.pendingCount() == 1)
    }

    @Test
    func pruningTombstonesStatesWhoseDayIsLongPast() async throws {
        let store = try store()
        try await store.apply(.markRead, to: ["payment:a:2026-01-15", "payment:a:2026-11-15", "price:x"])
        let november = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20)))
        try await store.pruneNotificationStates(now: november)
        #expect(try await store.fetchNotificationStates().map(\.id).sorted() == ["payment:a:2026-11-15", "price:x"])
        let deletes = try await store.pendingEvents(limit: 50).filter { $0.operation == "delete" }
        #expect(deletes.map(\.entityID) == ["payment:a:2026-01-15"])
    }

    @Test
    func aTombstoneIsFinal() async throws {
        let store = try store()
        try await store.apply(.markRead, to: ["payment:a:2026-01-15"])
        try await store.pruneNotificationStates(now: Date(timeIntervalSince1970: 1_800_000_000))
        try await store.apply(.restore, to: ["payment:a:2026-01-15"])
        #expect(try await store.fetchNotificationStates().isEmpty)
    }

    @Test
    func anotherDevicesRowIsStoredWithoutBeingQueuedBack() async throws {
        let store = try store()
        let row = """
        {"id":"\(id)","read_at":"2026-11-13T10:00:00.000Z","dismissed_at":"2026-11-13T10:05:00.000Z",\
        "created_at":"2026-11-13T10:00:00.000Z","updated_at":"2026-11-13T10:05:00.000Z","deleted_at":null}
        """
        try await store.applyRemote(entity: "notificationState", row: Data(row.utf8))
        let state = try #require(try await store.fetchNotificationStates().first)
        #expect(state.id == id)
        #expect(state.isRead)
        #expect(state.isDismissed)
        #expect(await store.pendingCount() == 0)

        // Undone there: the row comes back without `dismissed_at`.
        let undone = row.replacingOccurrences(of: "\"dismissed_at\":\"2026-11-13T10:05:00.000Z\"", with: "\"dismissed_at\":null")
        try await store.applyRemote(entity: "notificationState", row: Data(undone.utf8))
        #expect(try await store.fetchNotificationStates().first?.isDismissed == false)
    }

    @Test
    func aTombstoneFromTheServerRemovesItAndStaysFinal() async throws {
        let store = try store()
        try await store.apply(.markRead, to: [id])
        let tombstone = """
        {"id":"\(id)","read_at":null,"dismissed_at":null,"created_at":"2026-11-13T10:00:00.000Z",\
        "updated_at":"2026-11-14T10:00:00.000Z","deleted_at":"2026-11-14T10:00:00.000Z"}
        """
        try await store.applyRemote(entity: "notificationState", row: Data(tombstone.utf8))
        #expect(try await store.fetchNotificationStates().isEmpty)
        try await store.apply(.markRead, to: [id])
        #expect(try await store.fetchNotificationStates().isEmpty)
    }

    @Test
    func erasingThisIPhoneForgetsEveryState() async throws {
        let store = try store()
        try await store.apply(.markRead, to: [id])
        try await store.eraseAll()
        #expect(try await store.fetchNotificationStates().isEmpty)
    }

    @Test
    func replacingSyncedDataWithTheAccountsClearsLocalStatesAndAppliesTheirs() async throws {
        let store = try store()
        try await store.apply(.markRead, to: ["price:local"])
        let remote = """
        {"id":"price:remote","read_at":"2026-11-13T10:00:00.000Z","dismissed_at":null,\
        "created_at":"2026-11-13T10:00:00.000Z","updated_at":"2026-11-13T10:00:00.000Z","deleted_at":null}
        """
        try await store.replaceSyncedData(with: [RemoteRow(entity: "notificationState", row: Data(remote.utf8))])
        #expect(try await store.fetchNotificationStates().map(\.id) == ["price:remote"])
    }

    @Test
    func keepingThisIPhonesDataUploadsItsStates() async throws {
        let store = try store()
        try await store.apply(.markRead, to: ["price:local"])
        try await store.queueFullUpload(replacing: [], at: .now)
        let events = try await store.pendingEvents(limit: 50)
        #expect(events.contains { $0.entity == "notificationState" && $0.entityID == "price:local" })
    }
}
