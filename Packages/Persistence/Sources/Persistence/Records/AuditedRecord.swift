import Domain
import Foundation
import SwiftData

/// The `updatedAt` for a local write over a row stamped `previous`: `now`, or a millisecond after
/// `previous` when this device's clock is behind it. The server keeps the later stamp (ADR 0005), so
/// a clock running behind would otherwise lose the person's latest edit as `older_than_stored`. A
/// new row (no `previous`) gets `now`.
func stampAfter(_ previous: Date?, now: Date = .now) -> Date {
    guard let previous else { return now }
    return max(now, previous.addingTimeInterval(0.001))
}

extension PersistentModel {
    /// Inserted in its context and not saved yet: a new row, whose `updatedAt` is only its init default.
    var isNewlyInserted: Bool {
        modelContext?.insertedModelsArray.contains { $0.persistentModelID == persistentModelID } ?? false
    }
}

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
        updatedAt = nextUpdatedAt(now: now)
        deletedAt = nil
    }

    func stampDeleted(at now: Date = .now) {
        let stamp = nextUpdatedAt(now: now)
        updatedAt = stamp
        deletedAt = stamp
    }

    /// A change that isn't a save or a delete, such as a new place in the person's order.
    func stampChanged(at now: Date = .now) {
        updatedAt = nextUpdatedAt(now: now)
    }

    private func nextUpdatedAt(now: Date) -> Date {
        let isNew = (self as? any PersistentModel)?.isNewlyInserted ?? false
        return stampAfter(isNew ? nil : updatedAt, now: now)
    }

    /// Keeps the times a restored file carries instead of the moment of the restore.
    func apply(_ metadata: RecordMetadata) {
        createdAt = metadata.createdAt
        updatedAt = metadata.updatedAt
        deletedAt = metadata.deletedAt
    }
}
