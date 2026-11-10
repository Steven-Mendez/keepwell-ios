import Domain
import DomainSamples
import Foundation
import SwiftData
import Testing
@testable import Persistence

@Suite("SwiftData store soft deletes and audit dates")
struct SwiftDataStoreSyncTests {
    private let sample = SampleData.standard

    private func makeStore() throws -> SwiftDataStore {
        try SwiftDataStore(modelContainer: ModelContainerFactory.make(store: .inMemory))
    }

    private func seeded() async throws -> SwiftDataStore {
        let store = try makeStore()
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

    @Test
    func deletingKeepsATombstoneThatNoScreenSees() async throws {
        let store = try await seeded()
        let transaction = try #require(sample.transactions.first)
        let card = try #require(sample.cards.first)
        let account = try #require(sample.accounts.last)

        try await store.deleteTransaction(id: transaction.id)
        try await store.deleteCard(id: card.id)
        try await store.deleteAccount(id: account.id)

        #expect(try await !store.fetchTransactions(in: nil).contains { $0.id == transaction.id })
        #expect(try await !store.fetchCards().contains { $0.id == card.id })
        #expect(try await !store.fetchAccounts().contains { $0.id == account.id })
        let contents = try await store.auditedContents()
        #expect(contents.transactions.first { $0.value.id == transaction.id }?.metadata.isDeleted == true)
        #expect(contents.cards.first { $0.value.id == card.id }?.metadata.isDeleted == true)
        #expect(contents.accounts.first { $0.value.id == account.id }?.metadata.isDeleted == true)
        #expect(contents.transactions.count == sample.transactions.count)
    }

    @Test
    func deletingTwiceThrowsNotFound() async throws {
        let store = try await seeded()
        let id = try #require(sample.transactions.first?.id)
        try await store.deleteTransaction(id: id)
        await #expect(throws: DomainError.notFound(id)) { try await store.deleteTransaction(id: id) }
    }

    @Test
    func savingStampsTheChangeKeepsCreationAndBringsBackADeletedRecord() async throws {
        let store = try await seeded()
        let transaction = try #require(sample.transactions.first)
        let before = try #require(await store.auditedContents().transactions.first { $0.value.id == transaction.id })

        try await store.deleteTransaction(id: transaction.id)
        try await store.save(transaction.with(status: .planned))

        let after = try #require(await store.auditedContents().transactions.first { $0.value.id == transaction.id })
        #expect(after.metadata.createdAt == before.metadata.createdAt)
        #expect(after.metadata.updatedAt > before.metadata.updatedAt)
        #expect(!after.metadata.isDeleted)
        #expect(try await store.fetchTransactions(in: nil).contains { $0.id == transaction.id })
    }

    @Test
    func aDeletedCreatedCategoryStaysAsATombstone() async throws {
        let store = try makeStore()
        let boat = TransactionCategory(id: "custom-boat", name: "Boat", kind: .expense)
        try await store.save(boat)
        try await store.deleteCategory(id: boat.id)

        #expect(try await !store.fetchCategories().contains { $0.id == boat.id })
        let row = try #require(await store.auditedContents().categories.first { $0.value.id == boat.id })
        #expect(row.metadata.isDeleted)

        try await store.save(boat)
        #expect(try await store.fetchCategories().contains { $0.id == boat.id })
    }

    /// A device still on a version before V5 only knows `isRemoved`: when it brings a deleted
    /// default back, the `deletedAt` it can't see must not keep the category hidden here.
    @Test
    func aDefaultBroughtBackByAnOlderVersionShowsAgain() async throws {
        let container = try ModelContainerFactory.make(store: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        _ = try await store.fetchCategories()
        try await store.deleteCategory(id: "pets")

        let olderDevice = ModelContext(container)
        for record in try olderDevice.fetch(FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.id == "pets" })) {
            record.isRemoved = false
        }
        try olderDevice.save()

        let reopened = SwiftDataStore(modelContainer: container)
        #expect(try await reopened.fetchCategories().contains { $0.id == "pets" })
        let row = try #require(await reopened.auditedContents().categories.first { $0.value.id == "pets" })
        #expect(!row.metadata.isDeleted)
    }

    @Test
    func eraseAllLeavesNoTombstones() async throws {
        let store = try await seeded()
        try await store.deleteTransaction(id: #require(sample.transactions.first?.id))
        try await store.eraseAll()
        let contents = try await store.auditedContents()
        #expect(contents.transactions.isEmpty && contents.accounts.isEmpty && contents.cards.isEmpty)
        #expect(contents.recurringRules.isEmpty)
        #expect(contents.savingsGoals.isEmpty)
        #expect(contents.loans.isEmpty && contents.personalDebts.isEmpty)
    }
}
