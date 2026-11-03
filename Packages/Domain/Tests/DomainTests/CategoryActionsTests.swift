import DomainSamples
import Foundation
import Testing
@testable import Domain

@Suite("Category actions")
struct CategoryActionsTests {
    private let sample = SampleData.standard

    @Test
    func defaultsHaveUniqueIDsAndEndWithOther() {
        let ids = TransactionCategory.defaults.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(TransactionCategory.defaultExpense.last?.id == TransactionCategory.otherExpenseID)
        #expect(TransactionCategory.defaultIncome.last?.id == TransactionCategory.otherIncomeID)
        let allDefault = TransactionCategory.defaults.allSatisfy(\.isDefault)
        #expect(allDefault)
    }

    @Test
    func orderingPutsCreatedCategoriesBeforeOther() {
        let boat = TransactionCategory(id: "custom-boat", name: "Boat", kind: .expense)
        let tips = TransactionCategory(id: "custom-tips", name: "Tips", kind: .income)
        let ordered = TransactionCategory.ordered([tips, boat] + TransactionCategory.defaults.reversed())
        let expense = ordered.filter { $0.kind == .expense }.map(\.id)
        let income = ordered.filter { $0.kind == .income }.map(\.id)
        #expect(expense.suffix(2) == ["custom-boat", TransactionCategory.otherExpenseID])
        #expect(income.suffix(2) == ["custom-tips", TransactionCategory.otherIncomeID])
        #expect(TransactionCategory.ordered(TransactionCategory.defaults) == TransactionCategory.defaults)
    }

    @Test
    func creatingTrimsTheNameAndKeepsIconAndColor() async throws {
        let store = InMemoryStore()
        let created = try await DefaultSaveCategoryUseCase(categories: store)
            .execute(CategoryDraft(name: "  Boat  ", kind: .expense, icon: "sailboat", color: "blue"))
        #expect(created.name == "Boat")
        #expect(created.id.hasPrefix("custom-"))
        #expect(!created.isDefault)
        #expect(created.icon == "sailboat")
        #expect(created.color == "blue")
        #expect(await store.fetchCategories().contains(created))
    }

    @Test
    func creatingRejectsEmptyAndDuplicateNames() async {
        let useCase = DefaultSaveCategoryUseCase(categories: InMemoryStore())
        await #expect(throws: DomainError.missingName) {
            try await useCase.execute(CategoryDraft(name: "   ", kind: .expense))
        }
        await #expect(throws: DomainError.duplicateCategoryName("groceries")) {
            try await useCase.execute(CategoryDraft(name: "groceries", kind: .expense))
        }
        await #expect(throws: DomainError.unsupportedTransactionKind(.transfer)) {
            try await useCase.execute(CategoryDraft(name: "Moves", kind: .transfer))
        }
    }

    @Test
    func theSameNameIsFineForTheOtherKind() async throws {
        let created = try await DefaultSaveCategoryUseCase(categories: InMemoryStore())
            .execute(CategoryDraft(name: "Gifts", kind: .income))
        #expect(created.kind == .income)
    }

    @Test
    func editingKeepsTheIDAndKind() async throws {
        let store = InMemoryStore()
        let useCase = DefaultSaveCategoryUseCase(categories: store)
        let created = try await useCase.execute(CategoryDraft(name: "Boat", kind: .expense))
        let renamed = try await useCase.execute(CategoryDraft(id: created.id, name: "Sailing", kind: .income, icon: "sailboat"))
        #expect(renamed.id == created.id)
        #expect(renamed.kind == .expense)
        #expect(await store.fetchCategories().filter { $0.id == created.id } == [renamed])
    }

    @Test
    func defaultsCantBeEditedOrDeleted() async {
        let store = InMemoryStore()
        await #expect(throws: DomainError.defaultCategoryIsReadOnly("groceries")) {
            try await DefaultSaveCategoryUseCase(categories: store).execute(CategoryDraft(id: "groceries", name: "Market", kind: .expense))
        }
        await #expect(throws: DomainError.defaultCategoryIsReadOnly("groceries")) {
            try await DefaultDeleteCategoryUseCase(categories: store, transactions: store).execute(id: "groceries")
        }
    }

    @Test
    func deletingMovesItsMovementsToOther() async throws {
        let boat = TransactionCategory(id: "custom-boat", name: "Boat", kind: .expense)
        let expense = try #require(sample.transactions.first { $0.kind == .expense })
        let moved = expense.with(categoryID: boat.id)
        let store = InMemoryStore(transactions: [moved], categories: TransactionCategory.defaults + [boat])
        try await DefaultDeleteCategoryUseCase(categories: store, transactions: store).execute(id: boat.id)
        #expect(await store.fetchCategories().contains(boat) == false)
        #expect(await store.fetchTransactions(in: nil).map(\.categoryID) == [TransactionCategory.otherExpenseID])
    }

    @Test
    func listingReturnsThePickerOrder() async throws {
        let boat = TransactionCategory(id: "custom-boat", name: "Boat", kind: .expense)
        let store = InMemoryStore(categories: [boat] + TransactionCategory.defaults)
        let listed = try await DefaultGetCategoriesUseCase(categories: store).execute()
        #expect(listed.filter { $0.kind == .expense }.suffix(2).map(\.id) == [boat.id, TransactionCategory.otherExpenseID])
    }
}
