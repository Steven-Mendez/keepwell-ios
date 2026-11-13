import Domain
import Foundation

/// "Export backup": everything synced, as the JSON file keepwell-web reads too.
public protocol ExportBackupUseCase: Sendable {
    func execute(at now: Date) async throws(DomainError) -> Data
}

public struct DefaultExportBackupUseCase: ExportBackupUseCase {
    private let store: any LedgerBackupStore

    public init(store: any LedgerBackupStore) {
        self.store = store
    }

    public func execute(at now: Date) async throws(DomainError) -> Data {
        try await store.exportBackup(at: now)
    }
}

/// "Restore backup": only into an empty ledger (decided 2026-11-12: no merge, no replace), all or
/// nothing, and through the outbox so sync sends it like any change made here.
public protocol RestoreBackupUseCase: Sendable {
    func execute(_ data: Data, at now: Date) async throws(BackupRestoreError)
}

public struct DefaultRestoreBackupUseCase: RestoreBackupUseCase {
    private let store: any LedgerBackupStore

    public init(store: any LedgerBackupStore) {
        self.store = store
    }

    public func execute(_ data: Data, at now: Date) async throws(BackupRestoreError) {
        try await store.importBackup(data, at: now)
    }
}
