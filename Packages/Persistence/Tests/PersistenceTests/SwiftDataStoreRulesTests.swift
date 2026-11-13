import Domain
import DomainSamples
import Foundation
import SwiftData
import Testing
@testable import Persistence

@Suite("SwiftData store tags, categorization rules and loan payments")
struct SwiftDataStoreRulesTests {
    private func makeStore() throws -> SwiftDataStore {
        try SwiftDataStore(modelContainer: ModelContainerFactory.make(store: .inMemory))
    }

    private let uber = CategorizationRule(match: "Uber", categoryID: "transport", kind: .expense, tags: ["trabajo"])
    private let cafe = CategorizationRule(match: "Café", categoryID: "restaurants", kind: .expense)
    private let payroll = CategorizationRule(match: "Payroll", categoryID: "salary", kind: .income)

    @Test
    func rulesKeepTheirOrderWhichTheyCanChange() async throws {
        let store = try makeStore()
        for rule in [uber, cafe, payroll] {
            try await store.save(rule)
        }
        // Saving an existing rule keeps its place.
        try await store.save(CategorizationRule(id: uber.id, match: "UBER", categoryID: "transport", kind: .expense))
        #expect(try await store.fetchCategorizationRules().map(\.id) == [uber.id, cafe.id, payroll.id])
        #expect(try await store.fetchCategorizationRules().first?.match == "UBER")

        try await store.reorderCategorizationRules(ids: [payroll.id, uber.id])
        #expect(try await store.fetchCategorizationRules().map(\.id) == [payroll.id, uber.id, cafe.id])
    }

    /// Two offline devices can give rules the same `sortIndex`; the id decides, not the creation date.
    @Test
    func rulesWithTheSameIndexAreOrderedByID() async throws {
        let container = try ModelContainerFactory.make(store: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        let first = try CategorizationRule(
            id: #require(UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000000")),
            match: "Uber", categoryID: "transport", kind: .expense,
        )
        let tiedHigh = try CategorizationRule(
            id: #require(UUID(uuidString: "CCCCCCCC-0000-4000-8000-000000000000")),
            match: "Café", categoryID: "restaurants", kind: .expense,
        )
        let tiedLow = try CategorizationRule(
            id: #require(UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000000")),
            match: "Payroll", categoryID: "salary", kind: .income,
        )
        for rule in [first, tiedHigh, tiedLow] {
            try await store.save(rule)
        }

        let otherDevice = ModelContext(container)
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        for record in try otherDevice.fetch(FetchDescriptor<CategorizationRuleRecord>()) where record.id != first.id {
            record.sortIndex = 1
            // The higher id is the older one, so ordering by creation date would put it first.
            record.createdAt = record.id == tiedHigh.id ? created : created.addingTimeInterval(60)
        }
        try otherDevice.save()

        let reopened = SwiftDataStore(modelContainer: container)
        #expect(try await reopened.fetchCategorizationRules().map(\.id) == [first.id, tiedLow.id, tiedHigh.id])
    }

    @Test
    func deletingARuleLeavesATombstone() async throws {
        let store = try makeStore()
        try await store.save(uber)
        try await store.save(cafe)
        try await store.deleteCategorizationRule(id: uber.id)
        #expect(try await store.fetchCategorizationRules() == [cafe])
        await #expect(throws: DomainError.notFound(uber.id)) { try await store.deleteCategorizationRule(id: uber.id) }
        let exported = try await store.auditedContents().categorizationRules
        #expect(exported.map(\.value) == [uber, cafe])
        #expect(exported.map(\.metadata.isDeleted) == [true, false])
    }

    @Test
    func tagsRoundTripOnMovementsAndRecurringRules() async throws {
        let sample = SampleData.standard
        let store = try makeStore()
        let movement = try #require(sample.transactions.first).with(categoryID: "transport", tags: ["Viaje México", "boda"])
        let rule = try #require(sample.recurringRules.first)
        let tagged = RecurringRule(
            id: rule.id, name: rule.name, kind: rule.kind, categoryID: rule.categoryID, amount: rule.amount,
            currency: rule.currency, accountID: rule.accountID, cardID: rule.cardID, frequency: rule.frequency,
            startDate: rule.startDate, tags: ["gym"],
        )
        try await store.save(movement)
        try await store.save(tagged)
        try await store.save(uber)
        #expect(try await store.fetchTransactions(in: nil).first?.tags == ["viaje-méxico", "boda"])
        #expect(try await store.fetchRecurringRules().first?.tags == ["gym"])
    }

    @Test
    func payingAnInstallmentSavesTheMovementAndTheLoanTogether() async throws {
        let sample = SampleData.standard
        let store = try makeStore()
        let loan = try #require(sample.loans.first)
        try await store.save(loan)
        let expense = try #require(sample.transactions.first { $0.kind == .expense })
        let paid = try loan.paying(at: expense.date, transactionID: expense.id)

        try await store.save(paid, recording: expense)
        #expect(try await store.fetchLoans() == [paid])
        #expect(try await store.fetchTransactions(in: nil).contains { $0.id == expense.id })

        let number = try #require(paid.payments.last?.number)
        let (unpaid, payment) = try paid.unpaying(number: number)
        try await store.save(unpaid, deletingTransaction: payment.transactionID)
        #expect(try await store.fetchLoans() == [unpaid])
        #expect(try await !store.fetchTransactions(in: nil).contains { $0.id == expense.id })
        #expect(try await store.auditedContents().transactions.contains { $0.value.id == expense.id && $0.metadata.isDeleted })
        // The movement may already be gone: the loan still saves.
        try await store.save(loan, deletingTransaction: UUID())
        #expect(try await store.fetchLoans() == [loan])
    }
}
