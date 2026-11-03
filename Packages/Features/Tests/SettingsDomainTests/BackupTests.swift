import Domain
import DomainSamples
import Foundation
import Testing
@testable import SettingsDomain

@Suite("Backup and restore")
struct BackupTests {
    private let sample = SampleData.standard

    private func create(_ store: InMemoryStore) async throws -> Data {
        try await DefaultCreateBackupUseCase(settings: store, accounts: store, cards: store, categories: store, transactions: store)
            .execute()
    }

    private func restore(_ data: Data, into store: InMemoryStore) async throws -> RestoreSummary {
        try await DefaultRestoreBackupUseCase(
            eraser: store, settings: store, accounts: store, cards: store, categories: store, transactions: store,
        ).execute(data)
    }

    @Test
    func aBackupRestoresEverythingAsItWas() async throws {
        let original = InMemoryStore(sample: sample)
        let backup = try await create(original)

        let other = InMemoryStore(sample: sample)
        for transaction in sample.transactions.prefix(3) {
            try await other.deleteTransaction(id: transaction.id)
        }
        let summary = try await restore(backup, into: other)

        #expect(summary.transactions == sample.transactions.count)
        #expect(summary.accounts == sample.accounts.count)
        #expect(await Set(other.fetchTransactions(in: nil)) == Set(sample.transactions))
        #expect(await Set(other.fetchCards()) == Set(sample.cards))
        #expect(await other.load()?.currencies == sample.settings.currencies)
    }

    @Test
    func aFileThatIsntABackupChangesNothing() async throws {
        let store = InMemoryStore(sample: sample)
        await #expect(throws: DomainError.self) {
            _ = try await restore(Data("date,amount\n2026-10-01,3".utf8), into: store)
        }
        #expect(await store.fetchTransactions(in: nil).count == sample.transactions.count)
    }

    @Test
    func aFrozenCardStaysFrozenThroughABackup() async throws {
        let store = InMemoryStore(sample: sample)
        let holder = try #require(sample.cards.first { $0.id == SampleData.IDs.mastercardHolder })
        await store.save(holder.with(isFrozen: true))
        let backup = try await create(store)
        let restored = InMemoryStore(sample: sample)
        _ = try await restore(backup, into: restored)
        #expect(await restored.fetchCards().first { $0.id == holder.id }?.isFrozen == true)
    }
}
