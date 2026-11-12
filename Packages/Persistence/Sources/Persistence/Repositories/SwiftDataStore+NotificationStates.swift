import Domain
import Foundation
import SwiftData

extension SwiftDataStore: NotificationStateRepository {
    public func fetchNotificationStates() throws(DomainError) -> [NotificationState] {
        try perform { context in
            try context.fetch(FetchDescriptor<NotificationStateRecord>(
                predicate: #Predicate { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.id)],
            ))
            .map { $0.toDomain() }
        }
    }

    public func apply(_ change: NotificationState.Change, to ids: [String]) throws(DomainError) {
        try perform { context in
            let now = Date.now
            var seen = Set<String>()
            for id in ids where seen.insert(id).inserted {
                let existing = try context.fetch(FetchDescriptor<NotificationStateRecord>(predicate: #Predicate { $0.id == id })).first
                // A tombstone is final (ADR 0005): the id is long past and won't be computed again.
                if let existing, existing.deletedAt != nil {
                    continue
                }
                let before = existing?.toDomain() ?? NotificationState(id: id)
                let after = before.applying(change, at: now)
                if existing != nil, after == before {
                    continue
                }
                let record = existing ?? NotificationStateRecord(id: id).inserted(into: context)
                record.readAt = after.readAt
                record.dismissedAt = after.dismissedAt
                record.stampSaved(at: now)
            }
            try context.saveWithOutbox(at: now)
        }
    }

    public func pruneNotificationStates(now: Date) throws(DomainError) {
        try perform { context in
            let live = try context.fetch(FetchDescriptor<NotificationStateRecord>(predicate: #Predicate { $0.deletedAt == nil }))
            for record in live where NotificationState.isStale(id: record.id, now: now) {
                record.stampDeleted()
            }
            try context.saveWithOutbox()
        }
    }
}
