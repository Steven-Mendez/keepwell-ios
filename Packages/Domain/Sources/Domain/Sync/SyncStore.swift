import Foundation

/// One pending local change, as the sync engine sends it (ADR 0005 in keepwell-api).
public struct OutboxEvent: Sendable, Equatable {
    public let id: UUID
    public let entity: String
    public let entityID: String
    public let operation: String
    /// The wire row, JSON.
    public let payload: Data
    public let createdAt: Date

    public init(id: UUID, entity: String, entityID: String, operation: String, payload: Data, createdAt: Date) {
        self.id = id
        self.entity = entity
        self.entityID = entityID
        self.operation = operation
        self.payload = payload
        self.createdAt = createdAt
    }
}

/// What the sync engine needs from local storage. `applyRemote` is the silent write path: it
/// stores a row from the server without queueing it back, and never revives a local tombstone.
public protocol SyncStore: Sendable {
    func pendingEvents(limit: Int) async throws(DomainError) -> [OutboxEvent]
    func removeEvents(ids: [UUID]) async throws(DomainError)
    func pendingCount() async -> Int
    func hasPendingEvent(entity: String, entityID: String) async -> Bool
    /// `false` when the row was ignored (a local tombstone, or an entity this app doesn't keep).
    @discardableResult
    func applyRemote(entity: String, row: Data) async throws(DomainError) -> Bool
    /// The server stored a change with another `updated_at` (it caps clocks that run ahead).
    func adoptUpdatedAt(entity: String, entityID: String, updatedAt: Date) async throws(DomainError)
}
