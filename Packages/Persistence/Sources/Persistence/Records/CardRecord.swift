import Domain
import Foundation
import SwiftData

@Model
public final class CardRecord {
    /// Kinds the app no longer has. Their rows are skipped when reading rather than migrated away:
    /// CloudKit-backed stores can't drop an attribute or a row type in a schema change, and an
    /// additional card's purchases already belong to its credit account, so they stay listed there.
    static let retiredKinds = ["creditAdditional"]

    public var id = UUID()
    var accountID = UUID()
    var kindRaw = CardKind.debit.rawValue
    var networkRaw: String?
    var lastFour: String?
    var colorRaw: String?
    // Additional-card controls, from when cards could have additionals. Kept in the schema
    // because CloudKit can't remove attributes; nothing reads or writes them anymore.
    var holderName: String?
    var capAmount: String?
    var capCurrency: String?
    /// Comma-separated category ids; a plain string syncs to CloudKit without a transformer.
    var allowedCategoryIDs = ""
    var defaultCategoryID: String?
    var alertEachPurchase = true
    var alertNearCap = true
    /// From when cards could be frozen; kept because CloudKit can't remove attributes.
    var isFrozen = false
    var createdAt = Date.now
    var productName: String?
    /// Kept as two numbers rather than a date: the plastic only prints month and year.
    var expiryMonth: Int?
    var expiryYear: Int?

    init(id: UUID) {
        self.id = id
    }

    func update(from card: Card) {
        accountID = card.accountID
        kindRaw = card.kind.rawValue
        networkRaw = card.network?.rawValue
        lastFour = card.lastFour
        colorRaw = card.color?.rawValue
        productName = card.productName
        expiryMonth = card.expiry?.month
        expiryYear = card.expiry?.year
    }

    func toDomain() throws(DomainCorruption) -> Card {
        guard let kind = CardKind(rawValue: kindRaw) else { throw DomainCorruption("Card kind \(kindRaw)") }
        do {
            return try Card(
                id: id,
                accountID: accountID,
                kind: kind,
                network: networkRaw.flatMap(CardNetwork.init(rawValue:)),
                lastFour: lastFour,
                color: colorRaw.flatMap(CardColor.init(rawValue:)),
                productName: productName,
                expiry: expiryMonth.flatMap { month in expiryYear.flatMap { try? CardExpiry(month: month, year: $0) } },
            )
        } catch {
            throw DomainCorruption("Card: \(error)")
        }
    }
}
