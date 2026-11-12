import Domain
import DomainSamples
import Foundation
import Testing
@testable import Persistence

/// A device whose clock runs behind must still stamp an edit after the row it changes, or the
/// server keeps the older row and drops the edit (`older_than_stored`).
@Suite("Monotonic updatedAt with the clock behind")
struct SwiftDataStoreClockTests {
    private let sample = SampleData.standard

    private func seeded() async throws -> SwiftDataStore {
        let store = try SwiftDataStore(modelContainer: ModelContainerFactory.make(store: .inMemory))
        try await store.seed(
            settings: sample.settings,
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
        return store
    }

    /// The stored row is three minutes ahead of this device's clock.
    private var stored: Date { Date.now.addingTimeInterval(180) }

    @Test
    func theRuleStampsAfterTheStoredRowOnlyWhenTheClockIsBehind() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let ahead = now.addingTimeInterval(180)
        #expect(stampAfter(ahead, now: now) == ahead.addingTimeInterval(0.001))
        #expect(stampAfter(now.addingTimeInterval(-60), now: now) == now)
        #expect(stampAfter(nil, now: now) == now)
    }

    @Test
    func savingAndDeletingStampAfterTheStoredRow() async throws {
        let store = try await seeded()
        let account = try #require(sample.accounts.first)
        let transaction = try #require(sample.transactions.first)
        let accountStamp = stored
        let transactionStamp = stored
        try await store.adoptUpdatedAt(entity: "account", entityID: account.id.uuidString.lowercased(), updatedAt: accountStamp)
        try await store.adoptUpdatedAt(entity: "transaction", entityID: transaction.id.uuidString.lowercased(), updatedAt: transactionStamp)

        try await store.save(account)
        try await store.deleteTransaction(id: transaction.id)

        let contents = try await store.auditedContents()
        let savedAccount = try #require(contents.accounts.first { $0.value.id == account.id })
        let deleted = try #require(contents.transactions.first { $0.value.id == transaction.id })
        #expect(savedAccount.metadata.updatedAt > accountStamp)
        #expect(deleted.metadata.updatedAt > transactionStamp)
        #expect(deleted.metadata.isDeleted)
    }

    @Test
    func reorderingStampsAfterTheStoredRow() async throws {
        let store = try await seeded()
        let rule = try #require(sample.categorizationRules.first)
        let stamp = stored
        try await store.adoptUpdatedAt(entity: "categorizationRule", entityID: rule.id.uuidString.lowercased(), updatedAt: stamp)

        try await store.reorderCategorizationRules(ids: sample.categorizationRules.map(\.id).reversed())

        let moved = try #require(await store.auditedContents().categorizationRules.first { $0.value.id == rule.id })
        #expect(moved.metadata.updatedAt > stamp)
    }

    @Test
    func aNewRowGetsTheCurrentTime() async throws {
        let store = try await seeded()
        let account = try #require(sample.accounts.first)
        let fresh = Account(
            name: "New",
            kind: account.kind,
            openingBalances: account.openingBalances,
            openingDate: account.openingDate,
            creditTerms: account.creditTerms,
        )
        let before = Date.now
        try await store.save(fresh)
        let after = Date.now

        let saved = try #require(await store.auditedContents().accounts.first { $0.value.id == fresh.id })
        #expect(saved.metadata.updatedAt >= before)
        #expect(saved.metadata.updatedAt <= after)
    }
}
