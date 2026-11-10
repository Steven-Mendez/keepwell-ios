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
}
