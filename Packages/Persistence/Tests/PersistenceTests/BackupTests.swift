import Domain
import DomainSamples
import Foundation
import Testing
@testable import Persistence

/// The full JSON backup: export, then restore into an empty ledger through the outbox.
@Suite("Backup")
struct BackupTests {
    private let sample = SampleData.standard
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore() throws -> SwiftDataStore {
        try SwiftDataStore(modelContainer: ModelContainerFactory.make(store: .inMemory))
    }

    private func device() async throws -> SwiftDataStore {
        let store = try makeStore()
        var settings = sample.settings
        settings.unlockMethod = .passcode
        try await store.seed(
            settings: settings,
            accounts: sample.accounts,
            cards: sample.cards,
            transactions: sample.transactions,
            categories: sample.categories,
            recurringRules: sample.recurringRules,
            savingsGoals: sample.savingsGoals,
            loans: sample.loans,
            personalDebts: sample.personalDebts,
            categorizationRules: sample.categorizationRules,
        )
        try await store.deleteTransaction(id: sample.transactions[0].id)
        try await store.deleteCategory(id: "gifts")
        return store
    }

    /// What "Delete all my data" and an onboarding without accounts leave.
    private func emptyLedger() async throws -> SwiftDataStore {
        let store = try makeStore()
        _ = try await store.fetchCategories()
        try await store.save(Settings(currencies: CurrencySettings(principal: "EUR", second: nil, rate: 1), hasCompletedOnboarding: true))
        return store
    }

    private struct Ledger: Equatable {
        let accounts: [Account]
        let cards: [Card]
        let transactions: [Transaction]
        let categories: [TransactionCategory]
        let recurringRules: [RecurringRule]
        let savingsGoals: [SavingsGoal]
        let loans: [Loan]
        let personalDebts: [PersonalDebt]
        let categorizationRules: [CategorizationRule]
        let currencies: CurrencySettings?
    }

    private func ledger(_ store: SwiftDataStore) async throws -> Ledger {
        try await Ledger(
            accounts: store.fetchAccounts().sorted { $0.id.uuidString < $1.id.uuidString },
            cards: store.fetchCards().sorted { $0.id.uuidString < $1.id.uuidString },
            transactions: store.fetchTransactions(in: nil).sorted { $0.id.uuidString < $1.id.uuidString },
            categories: store.fetchCategories(),
            recurringRules: store.fetchRecurringRules().sorted { $0.id.uuidString < $1.id.uuidString },
            savingsGoals: store.fetchSavingsGoals().sorted { $0.id.uuidString < $1.id.uuidString },
            loans: store.fetchLoans().sorted { $0.id.uuidString < $1.id.uuidString },
            personalDebts: store.fetchPersonalDebts().sorted { $0.id.uuidString < $1.id.uuidString },
            categorizationRules: store.fetchCategorizationRules(),
            currencies: store.load()?.currencies,
        )
    }

    /// Rows per entity in a backup, tombstones included.
    private func counts(_ data: Data) throws -> [String: Int] {
        let file = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entities = try #require(file["entities"] as? [String: [Any]])
        return entities.mapValues(\.count)
    }

    @Test
    func exportEmptyAndImportLeavesTheSameLedger() async throws {
        let source = try await device()
        let backup = try await source.exportBackup(at: now)

        let restored = try await emptyLedger()
        #expect(try await restored.isLedgerEmpty())
        try await restored.importBackup(backup, at: now)

        #expect(try await ledger(restored) == ledger(source))
        #expect(try await counts(restored.exportBackup(at: now)) == counts(backup))
        // This iPhone's own choices never travel in a backup.
        #expect(try await restored.load()?.unlockMethod == .biometrics)
        #expect(try await restored.load()?.hasCompletedOnboarding == true)
    }

    @Test
    func restoresThroughTheOutboxWithOneEventPerRowStampedAfterTheBackup() async throws {
        let backup = try await device().exportBackup(at: now)
        let restored = try await emptyLedger()
        try await restored.removeEvents(ids: restored.pendingEvents(limit: 10000).map(\.id))
        let later = now.addingTimeInterval(3600)

        try await restored.importBackup(backup, at: later)

        let events = try await restored.pendingEvents(limit: 10000)
        #expect(try events.count == counts(backup).values.reduce(0, +))
        #expect(events.first?.entity == "settings")
        for event in events {
            let row = try #require(JSONSerialization.jsonObject(with: event.payload) as? [String: Any])
            let updated = try #require((row["updated_at"] as? String).flatMap(WireReader.parse))
            #expect(updated >= later)
            #expect(event.operation == (row["deleted_at"] is NSNull ? "create" : "delete"))
        }
        #expect(events.filter { $0.operation == "delete" }.map(\.entityID).sorted()
            == [sample.transactions[0].id.uuidString.lowercased(), "gifts"].sorted())
    }

    @Test
    func onlyRestoresIntoAnEmptyLedgerAndWritesNothingOtherwise() async throws {
        let store = try await device()
        let backup = try await store.exportBackup(at: now)
        let pending = await store.pendingCount()
        #expect(try await store.isLedgerEmpty() == false)

        await #expect(throws: BackupRestoreError.notEmpty) { try await store.importBackup(backup, at: now) }
        #expect(await store.pendingCount() == pending)
    }

    @Test
    func emptyMeansNoDataRowsDeletedOnesIncludedAndOnlyShippedCategories() async throws {
        let store = try await emptyLedger()
        try await store.save(TransactionCategory(id: "groceries", name: "Food", kind: .expense, isRenamed: true))
        try await store.deleteCategory(id: "gifts")
        #expect(try await store.isLedgerEmpty())

        let custom = TransactionCategory(id: "custom-pets", name: "Pets", kind: .expense)
        try await store.save(custom)
        try await store.deleteCategory(id: custom.id)
        #expect(try await store.isLedgerEmpty() == false)

        let other = try await emptyLedger()
        let goal = try #require(sample.savingsGoals.first)
        try await other.save(goal)
        try await other.deleteSavingsGoal(id: goal.id)
        #expect(try await other.isLedgerEmpty() == false)
    }

    @Test
    func rejectsADamagedFileWholeAndWritesNothing() async throws {
        let backup = try await device().exportBackup(at: now)
        var file = try #require(JSONSerialization.jsonObject(with: backup) as? [String: Any])
        var entities = try #require(file["entities"] as? [String: [[String: Any]]])
        entities["transaction"]?[3]["amount"] = "12,50"
        file["entities"] = entities
        let damaged = try JSONSerialization.data(withJSONObject: file)
        let store = try await emptyLedger()
        let before = await store.pendingCount()

        await #expect(throws: BackupRestoreError.invalid("transaction[3]: amount")) { try await store.importBackup(damaged, at: now) }
        #expect(await store.pendingCount() == before)
        #expect(try await store.fetchAccounts().isEmpty)
    }

    @Test
    func rejectsFilesThatAreNotBackupsOrFromANewerVersion() async throws {
        let store = try await emptyLedger()
        await #expect(throws: BackupRestoreError.notBackup) { try await store.importBackup(Data("{ not json".utf8), at: now) }
        await #expect(throws: BackupRestoreError.notBackup) { try await store.importBackup(Data(#"{"accounts":[]}"#.utf8), at: now) }
        let newer = Data(#"{"format":"keepwell-backup","version":4,"exported_at":"2026-11-12T00:00:00.000Z","entities":{}}"#.utf8)
        await #expect(throws: BackupRestoreError.newerVersion(4)) { try await store.importBackup(newer, at: now) }
        let unknown = Data(#"{"format":"keepwell-backup","version":1,"exported_at":"2026-11-12T00:00:00.000Z","entities":{"budget":[]}}"#
            .utf8)
        await #expect(throws: BackupRestoreError.invalid("entities: unknown entity budget")) {
            try await store.importBackup(unknown, at: now)
        }
    }

    /// Version 2 added `closed_at`, so a closed account comes back closed.
    @Test
    func keepsAClosedAccountClosed() async throws {
        let source = try await device()
        let closing = now.addingTimeInterval(-86400)
        let account = try #require(sample.accounts.first)
        try await source.save(account.with(closedAt: closing))
        let backup = try await source.exportBackup(at: now)
        let file = try #require(JSONSerialization.jsonObject(with: backup) as? [String: Any])
        #expect(file["version"] as? Int == 3)

        let restored = try await emptyLedger()
        try await restored.importBackup(backup, at: now)

        let accounts = try await restored.fetchAccounts()
        #expect(accounts.first { $0.id == account.id }?.closedAt == closing)
        #expect(accounts.count { !$0.isOpen } == 1)
    }

    /// A file keepwell-web exported (`backup-web-v1.json`) restores here with every row.
    @Test
    func restoresABackupMadeOnTheWeb() async throws {
        let url = try #require(Bundle.module.url(forResource: "backup-web-v1", withExtension: "json", subdirectory: "Fixtures"))
        let backup = try Data(contentsOf: url)
        let store = try await emptyLedger()

        try await store.importBackup(backup, at: now)

        #expect(try await store.fetchAccounts().count == 5)
        #expect(try await store.fetchTransactions(in: nil).count == 5)
        #expect(try await store.fetchLoans().first?.payments.map(\.number) == [1])
        #expect(try await store.fetchPersonalDebts().first?.repayments.map(\.amount) == [20])
        #expect(try await store.fetchCategories().contains { $0.id == "custom-pets" })
        #expect(try await store.fetchCategories().contains { $0.id == "gifts" } == false)
        #expect(try await store.load()?.currencies.principal == "USD")
        // The web's version 1 file predates merchants, which an export lists (none).
        #expect(try await counts(store.exportBackup(at: now)).filter { $0.key != "merchant" } == counts(backup))
    }

    /// `BackupColumns` is `wire-columns.json` written out; a change to the wire format updates both.
    @Test
    func backupColumnsMatchTheSharedFixture() throws {
        struct Column: Decodable {
            let type: String
            let nullable: Bool
            let optional: Bool
        }
        struct File: Decodable {
            let entities: [String: [String: Column]]
        }
        let url = try #require(Bundle.module.url(forResource: "wire-columns", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).entities
        #expect(Set(BackupColumns.entities.keys) == Set(fixture.keys))
        #expect(Set(BackupFile.entities) == Set(fixture.keys))
        for (entity, columns) in fixture {
            let ours = Dictionary(uniqueKeysWithValues: (BackupColumns.entities[entity] ?? []).map { ($0.name, $0) })
            #expect(Set(ours.keys) == Set(columns.keys), "\(entity)")
            for (name, column) in columns {
                #expect(ours[name]?.type == column.type.first, "\(entity).\(name)")
                #expect(ours[name]?.nullable == column.nullable, "\(entity).\(name)")
                #expect(ours[name]?.optional == column.optional, "\(entity).\(name)")
            }
        }
    }
}
