import Domain
import DomainSamples
import Foundation
import Testing
@testable import Persistence

/// What one iPhone queues, another applies through the silent path and ends up with the same data:
/// the wire format is lossless for everything that syncs.
@Suite("Applying server rows")
struct ApplyRemoteTests {
    private func store() throws -> SwiftDataStore {
        try SwiftDataStore(modelContainer: ModelContainerFactory.make(store: .inMemory))
    }

    @Test
    func anotherIPhoneRebuildsTheSameDataFromTheRows() async throws {
        let sample = SampleData.standard
        let phone = try store()
        try await phone.save(sample.settings)
        for account in sample.accounts {
            try await phone.save(account)
        }
        for card in sample.cards {
            try await phone.save(card)
        }
        for transaction in sample.transactions {
            try await phone.save(transaction)
        }
        for rule in sample.recurringRules {
            try await phone.save(rule)
        }
        for goal in sample.savingsGoals {
            try await phone.save(goal)
        }
        for loan in sample.loans {
            try await phone.save(loan)
        }
        for debt in sample.personalDebts {
            try await phone.save(debt)
        }

        let other = try store()
        for event in try await phone.pendingEvents(limit: 10000) {
            try await other.applyRemote(entity: event.entity, row: event.payload)
        }
        #expect(await other.pendingCount() == 0)
        #expect(try await Set(other.fetchAccounts()) == Set(phone.fetchAccounts()))
        #expect(try await Set(other.fetchCards()) == Set(phone.fetchCards()))
        #expect(try await Set(other.fetchTransactions(in: nil)) == Set(phone.fetchTransactions(in: nil)))
        #expect(try await Set(other.fetchRecurringRules()) == Set(phone.fetchRecurringRules()))
        #expect(try await Set(other.fetchSavingsGoals()) == Set(phone.fetchSavingsGoals()))
        #expect(try await Set(other.fetchLoans()) == Set(phone.fetchLoans()))
        #expect(try await Set(other.fetchPersonalDebts()) == Set(phone.fetchPersonalDebts()))
        let settings = try #require(try await other.load())
        #expect(settings.currencies == sample.settings.currencies)
        #expect(settings.paymentReminderDaysBefore == sample.settings.paymentReminderDaysBefore)
    }

    @Test
    func aLocalTombstoneIsFinal() async throws {
        let account = try #require(SampleData.standard.accounts.first)
        let phone = try store()
        try await phone.save(account)
        let created = try #require(try await phone.pendingEvents().last)
        try await phone.deleteAccount(id: account.id)
        #expect(try await phone.applyRemote(entity: "account", row: created.payload) == false)
        #expect(try await phone.fetchAccounts().isEmpty)
    }

    @Test
    func theServerAdjustingUpdatedAtDoesNotQueueAnything() async throws {
        let account = try #require(SampleData.standard.accounts.first)
        let phone = try store()
        try await phone.save(account)
        try await phone.removeEvents(ids: phone.pendingEvents().map(\.id))
        try await phone.adoptUpdatedAt(entity: "account", entityID: account.id.uuidString.lowercased(), updatedAt: .now)
        #expect(await phone.pendingCount() == 0)
    }

    /// One iPhone deletes a category while another edits one of its movements before hearing of it:
    /// the later edit wins on the server and brings the deleted id back. The repair after the pull
    /// moves it to "Other", through the outbox; with nothing left to repair it writes nothing.
    @Test
    func aMovementEditedBeforeItsCategoryDeletionArrivedMovesToOther() async throws {
        let boat = TransactionCategory(id: "custom-boat", name: "Boat", kind: .expense)
        let expense = try #require(SampleData.standard.transactions.first { $0.kind == .expense })
        let movement = expense.with(categoryID: boat.id)
        let deleting = try store()
        let editing = try store()
        try await deleting.save(boat)
        try await deleting.save(movement)
        for event in try await deleting.pendingEvents(limit: 100) {
            try await editing.applyRemote(entity: event.entity, row: event.payload)
        }
        try await deleting.removeEvents(ids: deleting.pendingEvents(limit: 100).map(\.id))

        try await DefaultDeleteCategoryUseCase(categories: deleting, transactions: deleting).execute(id: boat.id)
        let edited = Transaction(
            id: movement.id, date: movement.date, status: movement.status, description: movement.description,
            kind: movement.kind, categoryID: boat.id, amount: movement.amount, currency: movement.currency,
            accountID: movement.accountID, cardID: movement.cardID, exchangeRate: movement.exchangeRate, note: "Vet",
        )
        try await editing.save(edited)
        try await editing.removeEvents(ids: editing.pendingEvents(limit: 100).map(\.id))
        // The pull brings the tombstone; the movement's own deletion-time move lost to the later edit.
        for event in try await deleting.pendingEvents(limit: 100) where event.entity == "category" {
            try await editing.applyRemote(entity: event.entity, row: event.payload)
        }
        #expect(try await editing.fetchTransactions(in: nil).first { $0.id == movement.id }?.categoryID == boat.id)

        let repair = DefaultReassignDeletedCategoriesUseCase(transactions: editing, recurringRules: editing)
        #expect(try await repair.execute(deletedCategoryIDs: editing.deletedCategoryIDs()) == 1)
        let repaired = try #require(try await editing.fetchTransactions(in: nil).first { $0.id == movement.id })
        #expect(repaired.categoryID == TransactionCategory.otherExpenseID)
        #expect(repaired.note == "Vet")
        #expect(try await editing.pendingEvents().map(\.entity) == ["transaction"])

        #expect(try await repair.execute(deletedCategoryIDs: editing.deletedCategoryIDs()) == 0)
        #expect(await editing.pendingCount() == 1)
    }
}
