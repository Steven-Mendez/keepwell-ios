import Foundation
import SwiftData

/// A local change waiting for the Keepwell API, written in the same `save()` as the change itself
/// (`ModelContext.saveWithOutbox()`), so a record can never change without its event. `payload` is
/// the row in the sync wire format shared with keepwell-web and the API (ADR 0005 there).
@Model
public final class OutboxRecord {
    public var id = UUID()
    /// Not `entity`: that name belongs to Core Data's `NSManagedObject`, under SwiftData, and
    /// using it crashes at save.
    var entityName = ""
    var entityID = ""
    /// `create`, `update` or `delete`.
    var operation = ""
    /// The wire row as JSON text.
    var payload = "{}"
    var createdAt = Date.now

    init(entity: String, entityID: String, operation: String, payload: String, createdAt: Date) {
        entityName = entity
        self.entityID = entityID
        self.operation = operation
        self.payload = payload
        self.createdAt = createdAt
    }
}
