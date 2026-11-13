import Foundation
import SwiftData

/// V13's shape of the records V14 changed, kept so a store written by V5 to V13 still opens and
/// migrates. Separate from `KeepwellSchema.swift` only to keep that file readable.
extension KeepwellSchemaV13 {
    /// The account row before it could be closed. V5 to V12 share it.
    @Model
    public final class AccountRecord {
        public var id = UUID()
        var name = ""
        var bank: String?
        var kindRaw = "deposit"
        var openingBalances = ""
        var openingDate = Date.distantPast
        var debtModeRaw: String?
        var limitAmount: String?
        var limitCurrency: String?
        var cutoffDay: Int?
        var dueDay: Int?
        var createdAt = Date.now
        var updatedAt = Date.now
        var deletedAt: Date?

        init() {}
    }
}
