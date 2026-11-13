import Foundation

/// Why a backup file couldn't be restored. Nothing is written in any of these cases.
public enum BackupRestoreError: Error, Equatable, Sendable {
    /// Not JSON, or JSON that isn't a Keepwell backup.
    case notBackup
    /// Made by a newer version of the app.
    case newerVersion(Int)
    /// A Keepwell backup with a damaged row; names the entity, row and column, never the value.
    case invalid(String)
    /// The ledger already holds the person's data (see `LedgerBackupStore.isLedgerEmpty`).
    case notEmpty
    /// Storage failed.
    case failed
}

/// The full backup (`keepwell-<date>.json`, the same file keepwell-web reads and writes): every row
/// of every synced entity, tombstones included, in the sync wire format. A restore goes only into an
/// empty ledger and through the outbox, like any local change, so sync pushes it.
public protocol LedgerBackupStore: Sendable {
    func exportBackup(at now: Date) async throws(DomainError) -> Data
    func importBackup(_ data: Data, at now: Date) async throws(BackupRestoreError)
    /// No account, card, movement, recurring rule, goal, loan, debt or categorization rule stored,
    /// deleted ones included, and no category but the shipped defaults (edited or deleted). Settings
    /// and notification states don't count: the backup's replace them.
    func isLedgerEmpty() async throws(DomainError) -> Bool
}
