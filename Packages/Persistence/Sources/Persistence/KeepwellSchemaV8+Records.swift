import Foundation
import SwiftData

/// V8's shape of the records V9 changed, kept so a store written by V6 to V8 still opens and
/// migrates. Separate from `KeepwellSchema.swift` only to keep that file readable.
extension KeepwellSchemaV8 {
    /// The movement row before it carried tags. V6 and V7 share it.
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

        #Index<TransactionRecord>([\.date])

        init(id: UUID, date: Date, amount: String, currency: String, accountID: UUID) {
            self.id = id
            self.date = date
            self.amount = amount
            self.currency = currency
            self.accountID = accountID
            ratePrincipal = currency
            rateSecond = currency
        }
    }

    /// The recurring rule row before it carried tags. V6 and V7 share it.
    @Model
    public final class RecurringRuleRecord {
        public var id = UUID()
        var name = ""
        var kindRaw = "expense"
        var categoryID: String?
        var amount = "0"
        var currency = ""
        var accountID = UUID()
        var cardID: UUID?
        var destinationAccountID: UUID?
        var frequencyRaw = "monthly"
        var interval = 1
        var startDate = Date.distantPast
        var nextDate = Date.distantPast
        var endDate: Date?
        var isSubscription = false
        var autoConfirm = false
        var isPaused = false
        var note: String?
        var createdAt = Date.now
        var updatedAt = Date.now
        var deletedAt: Date?

        #Index<RecurringRuleRecord>([\.nextDate])

        init(id: UUID, name: String, amount: String, currency: String, accountID: UUID, startDate: Date) {
            self.id = id
            self.name = name
            self.amount = amount
            self.currency = currency
            self.accountID = accountID
            self.startDate = startDate
            nextDate = startDate
        }
    }
}
