import Foundation
import SwiftData

/// V12's shape of the records V13 changed, kept so a store written by V9 to V12 still opens and
/// migrates. Separate from `KeepwellSchema.swift` only to keep that file readable.
extension KeepwellSchemaV12 {
    /// The personal debt row before it carried a due date. V9 to V11 share it.
    @Model
    public final class PersonalDebtRecord {
        public var id = UUID()
        var person = ""
        var directionRaw = "theyOweMe"
        var amount = "0"
        var currency = ""
        var date = Date.distantPast
        var note: String?
        var repaymentsJSON = "[]"
        var settledAt: Date?
        var transactionID: UUID?
        var createdAt = Date.now
        var updatedAt = Date.now
        var deletedAt: Date?

        init() {}
    }
}
