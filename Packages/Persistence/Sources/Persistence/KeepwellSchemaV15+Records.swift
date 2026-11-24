import Foundation
import SwiftData

/// V15's shape of the records V16 changed, kept so a store written by V15 still opens and migrates.
extension KeepwellSchemaV15 {
    /// The movement row before it could carry a shared split's link.
    @Model
    public final class TransactionRecord {
        public var id = UUID()
        var date = Date.distantPast
        var statusRaw = "confirmed"
        var descriptionText = ""
        var kindRaw = "expense"
        var categoryID: String?
        var amount = "0"
        var currency = ""
        var accountID = UUID()
        var cardID: UUID?
        var destinationAccountID: UUID?
        var actualDebitedPrincipal: String?
        var ratePrincipal = ""
        var rateSecond = ""
        var rate = "1"
        var isShared = false
        var note: String?
        var createdAt = Date.now
        var updatedAt = Date.now
        var deletedAt: Date?
        var recurringID: UUID?
        var tagsText = ""
        var sourceRaw: String?
        var merchantID: UUID?
        var viaMerchantID: UUID?

        #Index<TransactionRecord>([\.date])

        init() {}
    }
}
