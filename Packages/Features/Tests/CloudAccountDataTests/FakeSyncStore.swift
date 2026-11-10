import Domain
import Foundation

/// Local storage stand-in: records what the engine asks of it.
actor FakeSyncStore: SyncConflictStore {
    var events: [OutboxEvent] = []
    var applied: [(String, [String: Any])] = []
    var adopted: [(String, Date)] = []
    /// Live rows per entity, as `localRowCounts()` reports them.
    var counts: [String: Int] = [:]
    private(set) var replacedWith: [RemoteRow]?
    private(set) var uploadedOver: [RemoteRow]?

    init(events: [OutboxEvent] = [], counts: [String: Int] = [:]) {
        self.events = events
        self.counts = counts
    }

    func pendingEvents(limit: Int) throws(DomainError) -> [OutboxEvent] {
        Array(events.prefix(limit))
    }

    func removeEvents(ids: [UUID]) throws(DomainError) {
        events.removeAll { ids.contains($0.id) }
    }

    func pendingCount() -> Int {
        events.count
    }

    func hasPendingEvent(entity: String, entityID: String) -> Bool {
        events.contains { $0.entity == entity && $0.entityID == entityID }
    }

    func applyRemote(entity: String, row: Data) throws(DomainError) -> Bool {
        applied.append((entity, (try? JSONSerialization.jsonObject(with: row) as? [String: Any]) ?? [:]))
        return true
    }

    func adoptUpdatedAt(entity: String, entityID _: String, updatedAt: Date) throws(DomainError) {
        adopted.append((entity, updatedAt))
    }

    func localRowCounts() throws(DomainError) -> [String: Int] {
        counts
    }

    func replaceSyncedData(with rows: [RemoteRow]) throws(DomainError) {
        replacedWith = rows
        events = []
    }

    /// Stands in for the real upload: one delete per live remote row, enough to see it was sent.
    func queueFullUpload(replacing rows: [RemoteRow], at now: Date) throws(DomainError) {
        uploadedOver = rows
        events = rows.compactMap { remote in
            guard var row = try? JSONSerialization.jsonObject(with: remote.row) as? [String: Any], let id = row["id"] as? String
            else { return nil }
            row["deleted_at"] = "2026-11-10T00:00:00.000Z"
            return OutboxEvent(
                id: UUID(), entity: remote.entity, entityID: id, operation: "delete",
                payload: (try? JSONSerialization.data(withJSONObject: row)) ?? Data(), createdAt: now,
            )
        }
    }

    func appliedNames() -> [String] {
        applied.compactMap { $0.1["name"] as? String }
    }

    func appliedCount() -> Int {
        applied.count
    }

    func push(_ event: OutboxEvent) {
        events.append(event)
    }
}
