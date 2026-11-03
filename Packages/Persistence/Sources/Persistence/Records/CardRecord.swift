import Domain
import Foundation
import SwiftData

@Model
public final class CardRecord {
    public var id = UUID()
    var accountID = UUID()
    var kindRaw = CardKind.debit.rawValue
    var networkRaw: String?
    var lastFour: String?
    var colorRaw: String?
    var holderName: String?
    var capAmount: String?
    var capCurrency: String?
    /// Comma-separated category ids; a plain string syncs to CloudKit without a transformer.
    var allowedCategoryIDs = ""
    var defaultCategoryID: String?
    var alertEachPurchase = true
    var alertNearCap = true
    var isFrozen = false
    var createdAt = Date.now

    init(id: UUID) {
        self.id = id
    }

    func update(from card: Card) {
        accountID = card.accountID
        kindRaw = card.kind.rawValue
        networkRaw = card.network?.rawValue
        lastFour = card.lastFour
        colorRaw = card.color?.rawValue
        let controls = card.additional
        holderName = controls?.holderName
        capAmount = controls?.cycleCap.map { DecimalCoding.string($0.amount) }
        capCurrency = controls?.cycleCap?.currency
        allowedCategoryIDs = controls?.allowedCategoryIDs.joined(separator: ",") ?? ""
        defaultCategoryID = controls?.defaultCategoryID
        alertEachPurchase = controls?.alertEachPurchase ?? true
        alertNearCap = controls?.alertNearCap ?? true
        isFrozen = card.isFrozen
    }

    func toDomain() throws(DomainCorruption) -> Card {
        guard let kind = CardKind(rawValue: kindRaw) else { throw DomainCorruption("Card kind \(kindRaw)") }
        var controls: AdditionalCardControls?
        if kind == .creditAdditional {
            var cap: Money?
            if let capAmount, let capCurrency {
                cap = try Money(DecimalCoding.decimal(capAmount), capCurrency)
            }
            controls = AdditionalCardControls(
                holderName: holderName ?? "",
                cycleCap: cap,
                allowedCategoryIDs: allowedCategoryIDs.split(separator: ",").map(String.init),
                defaultCategoryID: defaultCategoryID,
                alertEachPurchase: alertEachPurchase,
                alertNearCap: alertNearCap,
                isFrozen: isFrozen,
            )
        }
        do {
            return try Card(
                id: id,
                accountID: accountID,
                kind: kind,
                network: networkRaw.flatMap(CardNetwork.init(rawValue:)),
                lastFour: lastFour,
                color: colorRaw.flatMap(CardColor.init(rawValue:)),
                additional: controls,
                isFrozen: isFrozen,
            )
        } catch {
            throw DomainCorruption("Card: \(error)")
        }
    }
}
