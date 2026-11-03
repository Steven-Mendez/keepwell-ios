import Domain
import DomainSamples
import Foundation
import SwiftData
import Testing
@testable import Persistence

@Suite("SwiftData store")
struct SwiftDataStoreTests {
    private let sample = SampleData.standard

    private func makeStore() throws -> SwiftDataStore {
        try SwiftDataStore(modelContainer: ModelContainerFactory.make(store: .inMemory))
    }

    @Test
    func accountsRoundTripIncludingCreditTerms() async throws {
        let store = try makeStore()
        for account in sample.accounts {
            try await store.save(account)
        }
        let fetched = try await store.fetchAccounts()
        #expect(Set(fetched) == Set(sample.accounts))
    }

    @Test
    func savingAMovementAnnouncesTheChange() async throws {
        // The app reloads home and the widgets on this notification, whichever screen saved.
        let store = try makeStore()
        let transaction = try #require(sample.transactions.first)
        try await confirmation(expectedCount: 1...) { saved in
            let observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { _ in
                saved()
            }
            defer { NotificationCenter.default.removeObserver(observer) }
            try await store.save(transaction)
        }
    }

    @Test
    func cardsRoundTripIncludingAdditionalControls() async throws {
        let store = try makeStore()
        for card in sample.cards {
            try await store.save(card)
        }
        #expect(try await Set(store.fetchCards()) == Set(sample.cards))
    }

    @Test
    func transactionsRoundTripExactlyAndNewestFirst() async throws {
        let store = try makeStore()
        for transaction in sample.transactions {
            try await store.save(transaction)
        }
        let fetched = try await store.fetchTransactions(in: nil)
        #expect(Set(fetched) == Set(sample.transactions))
        #expect(fetched.map(\.date) == fetched.map(\.date).sorted(by: >))
    }

    @Test
    func transactionsFilterByHalfOpenPeriod() async throws {
        let store = try makeStore()
        for transaction in sample.transactions {
            try await store.save(transaction)
        }
        let october = try #require(YearMonth(year: 2026, month: 10)?.dateInterval(in: .current))
        let fetched = try await store.fetchTransactions(in: october)
        #expect(!fetched.isEmpty)
        #expect(fetched.allSatisfy { $0.date >= october.start && $0.date < october.end })
    }

    @Test
    func savingTwiceUpdatesInsteadOfDuplicating() async throws {
        let store = try makeStore()
        let planned = try #require(sample.transactions.first { $0.status == .planned })
        try await store.save(planned)
        try await store.save(planned.confirmed())
        let fetched = try await store.fetchTransactions(in: nil)
        #expect(fetched == [planned.confirmed()])
    }

    @Test
    func deletingMissingRecordsThrowsNotFound() async throws {
        let store = try makeStore()
        let id = UUID()
        await #expect(throws: DomainError.notFound(id)) { try await store.deleteTransaction(id: id) }
        await #expect(throws: DomainError.notFound(id)) { try await store.deleteAccount(id: id) }
        await #expect(throws: DomainError.notFound(id)) { try await store.deleteCard(id: id) }
    }

    @Test
    func categoriesAreSeededOnceInDefaultOrder() async throws {
        let store = try makeStore()
        let first = try await store.fetchCategories()
        let second = try await store.fetchCategories()
        #expect(first == TransactionCategory.defaults)
        #expect(second == first)
    }

    @Test
    func createdCategoriesKeepIconAndColorAndComeBeforeOther() async throws {
        let store = try makeStore()
        _ = try await store.fetchCategories()
        let boat = TransactionCategory(id: "custom-boat", name: "Boat", kind: .expense, icon: "sailboat", color: "blue")
        try await store.save(boat)
        let fetched = try await store.fetchCategories().filter { $0.kind == .expense }
        #expect(fetched.last?.id == TransactionCategory.otherExpenseID)
        #expect(fetched.dropLast().last == boat)
    }

    @Test
    func defaultsAddedInANewVersionAppearForExistingData() async throws {
        let store = try makeStore()
        for category in TransactionCategory.defaults.prefix(5) {
            try await store.save(category)
        }
        let fetched = try await store.fetchCategories()
        #expect(fetched == TransactionCategory.defaults)
    }

    @Test
    func deletingACategoryRemovesItAndToleratesMissingIDs() async throws {
        let store = try makeStore()
        try await store.save(TransactionCategory(id: "custom-boat", name: "Boat", kind: .expense))
        try await store.deleteCategory(id: "custom-boat")
        try await store.deleteCategory(id: "custom-boat")
        #expect(try await store.fetchCategories() == TransactionCategory.defaults)
    }

    @Test
    func aDeletedDefaultStaysDeletedAcrossFetchesAndContexts() async throws {
        let container = try ModelContainerFactory.make(store: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        _ = try await store.fetchCategories()
        try await store.deleteCategory(id: "groceries")
        #expect(try await store.fetchCategories().contains { $0.id == "groceries" } == false)
        // A fresh actor on the same container re-runs seeding, which must respect the tombstone.
        let reopened = SwiftDataStore(modelContainer: container)
        #expect(try await reopened.fetchCategories().contains { $0.id == "groceries" } == false)
    }

    @Test
    func aDefaultDeletedBeforeSeedingIsNotSeeded() async throws {
        let store = try makeStore()
        try await store.deleteCategory(id: "pets")
        #expect(try await store.fetchCategories().contains { $0.id == "pets" } == false)
    }

    @Test
    func renamedDefaultsKeepTheFlagAndRestoringUndoesEverything() async throws {
        let store = try makeStore()
        _ = try await store.fetchCategories()
        let boat = TransactionCategory(id: "custom-boat", name: "Boat", kind: .expense)
        try await store.save(boat)
        let market = TransactionCategory(id: "groceries", name: "Market", kind: .expense, icon: "basket", color: "green", isRenamed: true)
        try await store.save(market)
        try await store.deleteCategory(id: "transport")
        try await store.reorderCategories(ids: ["custom-boat", "taxes"])
        let edited = try await store.fetchCategories()
        #expect(edited.first { $0.id == "groceries" } == market)
        #expect(edited.prefix(2).map(\.id) == ["custom-boat", "taxes"])

        try await store.restoreDefaultCategories()
        let restored = try await store.fetchCategories()
        let expense = restored.filter { $0.kind == .expense }
        #expect(expense.filter(\.isDefault) == TransactionCategory.defaultExpense)
        #expect(expense.suffix(2).map(\.id) == [boat.id, TransactionCategory.otherExpenseID])
        #expect(restored.filter { $0.kind == .income } == TransactionCategory.defaultIncome)
    }

    @Test
    func settingsKeepASingleRow() async throws {
        let store = try makeStore()
        #expect(try await store.load() == nil)
        try await store.save(sample.settings)
        var changed = sample.settings
        changed.unlockMethod = .passcode
        try await store.save(changed)
        #expect(try await store.load() == changed)
    }

    @Test
    func eraseAllRemovesEverything() async throws {
        let store = try makeStore()
        for account in sample.accounts {
            try await store.save(account)
        }
        for transaction in sample.transactions {
            try await store.save(transaction)
        }
        try await store.save(sample.settings)
        try await store.eraseAll()
        #expect(try await store.fetchAccounts().isEmpty)
        #expect(try await store.fetchTransactions(in: nil).isEmpty)
        #expect(try await store.load() == nil)
    }
}

@Suite("SwiftData store seeding")
struct SwiftDataStoreSeedTests {
    @Test
    func seedsTheWholeSample() async throws {
        let sample = SampleData.standard
        let store = try SwiftDataStore(modelContainer: ModelContainerFactory.make(store: .inMemory))
        try await store.seed(
            settings: sample.settings,
            accounts: sample.accounts,
            cards: sample.cards,
            transactions: sample.transactions,
            categories: sample.categories,
        )
        #expect(try await store.fetchAccounts().count == sample.accounts.count)
        #expect(try await store.fetchCards().count == sample.cards.count)
        #expect(try await store.fetchTransactions(in: nil).count == sample.transactions.count)
        #expect(try await store.load() == sample.settings)
    }
}
