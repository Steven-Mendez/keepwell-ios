import Domain
import Foundation

/// A record that keeps when it was created, changed and soft-deleted (`RecordMetadata`).
protocol AuditedRecord: AnyObject {
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
}

extension AuditedRecord {
    var metadata: RecordMetadata {
        RecordMetadata(createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }

    /// A save is a change, and saving a deleted record brings it back.
    func stampSaved(at now: Date = .now) {
        updatedAt = now
        deletedAt = nil
    }

    func stampDeleted(at now: Date = .now) {
        updatedAt = now
        deletedAt = now
    }

    /// Keeps the times a restored file carries instead of the moment of the restore.
    func apply(_ metadata: RecordMetadata) {
        createdAt = metadata.createdAt
        updatedAt = metadata.updatedAt
        deletedAt = metadata.deletedAt
    }
}
