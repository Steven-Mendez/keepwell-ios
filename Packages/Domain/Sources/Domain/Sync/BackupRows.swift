import Foundation

/// A record as the backup file writes it, which converts back to its domain value with its audit
/// times and checks itself on the way.
protocol StampedBackupRow {
    associatedtype Value: Hashable & Sendable
    func toDomain() throws(DomainError) -> Stamped<Value>
}

extension AccountBackup: StampedBackupRow {}
extension CardBackup: StampedBackupRow {}
extension CategoryBackup: StampedBackupRow {}
extension TransactionBackup: StampedBackupRow {}
extension RecurringRuleBackup: StampedBackupRow {}
extension SavingsGoalBackup: StampedBackupRow {}
extension LoanBackup: StampedBackupRow {}
extension PersonalDebtBackup: StampedBackupRow {}

extension Array where Element: StampedBackupRow {
    /// Every row converted in order; the first invalid one fails the whole file.
    func stamped() throws(DomainError) -> [Stamped<Element.Value>] {
        var values: [Stamped<Element.Value>] = []
        for row in self {
            try values.append(row.toDomain())
        }
        return values
    }
}
