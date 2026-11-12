import Domain
import Foundation
import SwiftData

extension SwiftDataStore: SyncStore {
    /// The oldest pending changes first, as they must reach the server.
    public func pendingEvents(limit: Int = 200) throws(DomainError) -> [OutboxEvent] {
        try perform { context in
            var descriptor = FetchDescriptor<OutboxRecord>(sortBy: [SortDescriptor(\.createdAt)])
            descriptor.fetchLimit = limit
            return try context.fetch(descriptor).map {
                OutboxEvent(
                    id: $0.id,
                    entity: $0.entityName,
                    entityID: $0.entityID,
                    operation: $0.operation,
                    payload: Data($0.payload.utf8),
                    createdAt: $0.createdAt,
                )
            }
        }
    }

    public func pendingCount() -> Int {
        (try? modelContext.fetchCount(FetchDescriptor<OutboxRecord>())) ?? 0
    }

    /// Removes answered events: the server has them (applied or stale) or refused them.
    public func removeEvents(ids: [UUID]) throws(DomainError) {
        try perform { context in
            let wanted = Set(ids)
            for record in try context.fetch(FetchDescriptor<OutboxRecord>()) where wanted.contains(record.id) {
                context.delete(record)
            }
            try context.save()
        }
    }

    public func hasPendingEvent(entity: String, entityID: String) -> Bool {
        let predicate = #Predicate<OutboxRecord> { $0.entityName == entity && $0.entityID == entityID }
        return ((try? modelContext.fetchCount(FetchDescriptor(predicate: predicate))) ?? 0) > 0
    }

    public func deletedCategoryIDs() throws(DomainError) -> Set<String> {
        try perform { context in
            try Set(context.fetch(FetchDescriptor<CategoryRecord>()).filter(\.isTombstone).map(\.id))
        }
    }
}
