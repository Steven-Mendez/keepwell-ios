import Domain
import Foundation
import SwiftData

@Model
public final class CategoryRecord {
    /// The category slug ("groceries", or "custom-…" for the person's own).
    public var id = ""
    var name = ""
    var kindRaw = TransactionKind.expense.rawValue
    /// Keeps the order stable across devices.
    var sortIndex = 0
    /// Added in V2; `nil` for defaults and for rows written by V1.
    var icon: String?
    var color: String?

    init(id: String) {
        self.id = id
    }

    func update(from category: TransactionCategory, sortIndex: Int) {
        name = category.name
        kindRaw = category.kind.rawValue
        icon = category.icon
        color = category.color
        self.sortIndex = sortIndex
    }

    func toDomain() throws(DomainCorruption) -> TransactionCategory {
        guard let kind = TransactionKind(rawValue: kindRaw) else { throw DomainCorruption("TransactionCategory kind \(kindRaw)") }
        return TransactionCategory(id: id, name: name, kind: kind, icon: icon, color: color)
    }
}
