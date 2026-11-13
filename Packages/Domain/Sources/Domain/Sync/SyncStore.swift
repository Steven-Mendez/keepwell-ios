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
    /// Ids of the categories that are tombstones here, for the repair after a pull.
    func deletedCategoryIDs() async throws(DomainError) -> Set<String>
}

/// A row as the server's snapshot sent it, for settling the first sync of this device with an
/// account whose cloud already holds data.
public struct RemoteRow: Sendable, Equatable {
    public let entity: String
    /// The wire row, JSON.
    public let row: Data

    public init(entity: String, row: Data) {
        self.entity = entity
        self.row = row
    }
}

/// The first sync of a device with an account when both sides hold data: one side is kept whole
/// and the other replaced (keepwell-web implements the same two resolutions).
public protocol SyncConflictStore: SyncStore {
    /// Live rows per sync entity (`account`, `transaction`…). Payments and repayments live inside
    /// their loan or debt, so a loan counts and its payments don't.
    func localRowCounts() async throws(DomainError) -> [String: Int]
    /// "Use your account's data": every synced row and the outbox go, then the account's rows are
    /// stored as the server's truth. This device's own settings (unlock, relock, hiding amounts)
    /// stay; the passcode, the name and the sync client id live outside the store.
    func replaceSyncedData(with rows: [RemoteRow]) async throws(DomainError)
    /// "Keep this iPhone's data": the outbox is rebuilt so every local row (tombstones included)
    /// goes up with an `updated_at` no older than the account's copy, and every live row of the
    /// account that this device doesn't have goes up as a tombstone. A delete always wins on the
    /// server and a tie goes to the later arrival, so the account ends up as this device is.
    func queueFullUpload(replacing rows: [RemoteRow], at now: Date) async throws(DomainError)
}
