import Foundation
import SwiftData

/// V14's shape of the records V15 changed, kept so a store written by V9 to V14 still opens and
/// migrates. Separate from `KeepwellSchema.swift` only to keep that file readable.
extension KeepwellSchemaV14 {
    /// The movement row before it named a merchant. V9 to V13 share it.
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

        #Index<TransactionRecord>([\.date])

        init() {}
    }

    /// The recurring rule row before it named a merchant. V9 to V13 share it.
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
        var tagsText = ""
        var sourceRaw: String?
        var createdAt = Date.now
        var updatedAt = Date.now
        var deletedAt: Date?

        #Index<RecurringRuleRecord>([\.nextDate])

        init() {}
    }

    /// The categorization rule row before it named a merchant. V9 to V13 share it.
    @Model
    public final class CategorizationRuleRecord {
        public var id = UUID()
        var match = ""
        var categoryID = ""
        var kindRaw = "expense"
        var tagsText = ""
        var sortIndex = 0
        var createdAt = Date.now
        var updatedAt = Date.now
        var deletedAt: Date?

        init() {}
    }
}
