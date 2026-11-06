import Domain
import Foundation
import SwiftData

@Model
public final class CategoryRecord: AuditedRecord {
    /// The category slug ("groceries", or "custom-…" for the person's own).
    public var id = ""
    var name = ""
    var kindRaw = TransactionKind.expense.rawValue
    /// Keeps the order stable across devices.
    var sortIndex = 0
    /// Added in V2; `nil` for defaults and for rows written by V1.
    var icon: String?
    var color: String?
    /// Added in V3. The person gave a default their own name, so it no longer translates.
    var isRenamed = false
    /// Added in V3. A deleted default stays as this tombstone, so seeding doesn't bring it back
    /// and the deletion syncs to the person's other devices.
    var isRemoved = false
    /// Added in V5. `isRemoved` stays in step with `deletedAt` for stores written before V5.
    var createdAt = Date.now
    var updatedAt = Date.now
    var deletedAt: Date?

    init(id: String) {
        self.id = id
    }

    /// `isRemoved` decides, not `deletedAt`: this version sets both together, but a device still on
    /// a version before V5 only knows `isRemoved`, and when it brings a default back the `deletedAt`
    /// it can't see must not keep the category hidden here.
    var isTombstone: Bool {
        isRemoved
    }

    func update(from category: TransactionCategory, sortIndex: Int) {
        name = category.name
        kindRaw = category.kind.rawValue
        icon = category.icon
        color = category.color
        isRenamed = category.isRenamed
        isRemoved = false
        self.sortIndex = sortIndex
    }

    func toDomain() throws(DomainCorruption) -> TransactionCategory {
        guard let kind = TransactionKind(rawValue: kindRaw) else { throw DomainCorruption("TransactionCategory kind \(kindRaw)") }
        return TransactionCategory(id: id, name: name, kind: kind, icon: icon, color: color, isRenamed: isRenamed)
    }
}
