import Foundation
import SwiftData

extension ModelContext {
    /// Saves with one outbox event per inserted or changed syncable record, in the same save. The
    /// only save path for local changes; rows that came from the server are saved with plain
    /// `save()` so they never go back (no echo).
    func saveWithOutbox(at now: Date = .now) throws {
        var offset = 0.0
        let inserted = Set(insertedModelsArray.map(\.persistentModelID))
        for model in insertedModelsArray + changedModelsArray {
            guard let pending = try PendingEvent(model, isNew: inserted.contains(model.persistentModelID)) else { continue }
            enqueue(
                entity: pending.entity,
                id: pending.id,
                operation: pending.operation,
                row: pending.row,
                at: now.addingTimeInterval(offset),
            )
            offset += 0.001
        }
        try save()
    }

    func enqueue(entity: String, id: String, operation: String, row: WireRow, at date: Date = .now) {
        insert(OutboxRecord(entity: entity, entityID: id, operation: operation, payload: Wire.json(row), createdAt: date))
    }
}

/// The event a changed model produces, if it syncs.
private struct PendingEvent {
    let entity: String
    let id: String
    let operation: String
    let row: WireRow

    init?(_ model: any PersistentModel, isNew: Bool) throws {
        switch model {
        case let record as any SyncableRecord:
            row = try record.wireRow()
            entity = type(of: record).syncEntity
            id = record.syncID
            operation = row["deleted_at"] is NSNull ? (isNew ? "create" : "update") : "delete"
        case let settings as SettingsRecord:
            row = settings.wireRow()
            entity = "settings"
            id = "settings"
            operation = "update"
        default:
            return nil
        }
    }
}
