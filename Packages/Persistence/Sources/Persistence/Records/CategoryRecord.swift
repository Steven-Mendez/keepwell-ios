import Domain
import Foundation
import SwiftData

@Model
public final class CategoryRecord {
    /// The category slug ("groceries").
    public var id = ""
    var name = ""
    var kindRaw = TransactionKind.expense.rawValue
    /// Keeps the default order stable across devices.
    var sortIndex = 0

    init(id: String) {
        self.id = id
    }

    func update(from category: TransactionCategory, sortIndex: Int) {
        name = category.name
        kindRaw = category.kind.rawValue
        self.sortIndex = sortIndex
    }

    func toDomain() throws(DomainCorruption) -> TransactionCategory {
        guard let kind = TransactionKind(rawValue: kindRaw) else { throw DomainCorruption("TransactionCategory kind \(kindRaw)") }
        return TransactionCategory(id: id, name: name, kind: kind)
    }
}
