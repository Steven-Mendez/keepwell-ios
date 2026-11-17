import Domain
import Foundation
import SwiftData

/// A business or platform (`Merchant`). Every property is optional or defaulted and nothing is
/// unique, as CloudKit requires.
@Model
public final class MerchantRecord: AuditedRecord {
    public var id = UUID()
    var name = ""
    var domain: String?
    var brandID: String?
    var defaultCategoryID: String?
    var isPlatform = false
    var createdAt = Date.now
    var updatedAt = Date.now
    var deletedAt: Date?

    init(id: UUID) {
        self.id = id
    }

    func update(from merchant: Merchant) {
        name = merchant.name
        domain = merchant.domain
        brandID = merchant.brandID
        defaultCategoryID = merchant.defaultCategoryID
        isPlatform = merchant.isPlatform
    }

    func toDomain() -> Merchant {
        Merchant(id: id, name: name, domain: domain, brandID: brandID, defaultCategoryID: defaultCategoryID, isPlatform: isPlatform)
    }
}
