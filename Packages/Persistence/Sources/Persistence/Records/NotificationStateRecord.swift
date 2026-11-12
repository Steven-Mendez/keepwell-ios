import Domain
import Foundation
import SwiftData

/// What the person did with one notification (read, deleted), keyed by the notification's id,
/// which is shared with the web and the server (ADR 0012 in keepwell-api). Every property is
/// optional or defaulted and nothing is unique, as CloudKit requires.
@Model
public final class NotificationStateRecord: AuditedRecord {
    public var id = ""
    var readAt: Date?
    var dismissedAt: Date?
    var createdAt = Date.now
    var updatedAt = Date.now
    var deletedAt: Date?

    init(id: String) {
        self.id = id
    }

    func toDomain() -> NotificationState {
        NotificationState(id: id, readAt: readAt, dismissedAt: dismissedAt)
    }
}
