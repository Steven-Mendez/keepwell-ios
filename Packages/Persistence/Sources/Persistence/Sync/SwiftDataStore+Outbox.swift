import Foundation
import SwiftData

/// One pending change, as the sync engine sends it.
public struct OutboxEvent: Sendable, Equatable {
    public let id: UUID
    public let entity: String
    public let entityID: String
    public let operation: String
    /// The wire row, JSON.
    public let payload: Data
    public let createdAt: Date
}

extension SwiftDataStore {
    /// The oldest pending changes first, as they must reach the server.
    public func pendingEvents(limit: Int = 200) throws(DomainErrorBridge) -> [OutboxEvent] {
        do {
            var descriptor = FetchDescriptor<OutboxRecord>(sortBy: [SortDescriptor(\.createdAt)])
            descriptor.fetchLimit = limit
            return try modelContext.fetch(descriptor).map {
                OutboxEvent(
                    id: $0.id,
                    entity: $0.entityName,
                    entityID: $0.entityID,
                    operation: $0.operation,
                    payload: Data($0.payload.utf8),
                    createdAt: $0.createdAt,
                )
            }
        } catch {
            throw DomainErrorBridge(error)
        }
    }

    public func pendingCount() -> Int {
        (try? modelContext.fetchCount(FetchDescriptor<OutboxRecord>())) ?? 0
    }

    /// Removes answered events; the server has them (applied or stale) or refused them.
    public func removeEvents(ids: [UUID]) throws(DomainErrorBridge) {
        do {
            let wanted = Set(ids)
            for record in try modelContext.fetch(FetchDescriptor<OutboxRecord>()) where wanted.contains(record.id) {
                modelContext.delete(record)
            }
            try modelContext.save()
        } catch {
            throw DomainErrorBridge(error)
        }
    }

    public func hasPendingEvent(entity: String, entityID: String) -> Bool {
        let predicate = #Predicate<OutboxRecord> { $0.entityName == entity && $0.entityID == entityID }
        return ((try? modelContext.fetchCount(FetchDescriptor(predicate: predicate))) ?? 0) > 0
    }
}

/// Wraps a SwiftData error for callers outside the store.
public struct DomainErrorBridge: Error, CustomStringConvertible {
    public let description: String
    init(_ error: any Error) {
        description = String(describing: error)
    }
}
