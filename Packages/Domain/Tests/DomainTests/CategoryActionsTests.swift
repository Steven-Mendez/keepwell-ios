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
    func orderingKeepsTheStoredOrderWithOtherLast() {
        let boat = TransactionCategory(id: "custom-boat", name: "Boat", kind: .expense)
        let tips = TransactionCategory(id: "custom-tips", name: "Tips", kind: .income)
        let stored = [tips] + TransactionCategory.defaults.reversed() + [boat]
        let ordered = TransactionCategory.ordered(stored)
        let expense = ordered.filter { $0.kind == .expense }.map(\.id)
        #expect(expense.first == TransactionCategory.loanPaymentsID)
        #expect(expense.suffix(2) == ["custom-boat", TransactionCategory.otherExpenseID])
        #expect(ordered.first(where: { $0.kind == .income }) == tips)
        #expect(ordered.last(where: { $0.kind == .income })?.id == TransactionCategory.otherIncomeID)
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
    func renamingADefaultStopsTranslatingItAndTheShippedNameRestoresIt() async throws {
        let store = InMemoryStore()
        let useCase = DefaultSaveCategoryUseCase(categories: store)
        let untouched = try #require(await store.fetchCategories().first { $0.id == "groceries" })
        #expect(untouched.translatesByID)

        let renamed = try await useCase.execute(CategoryDraft(
            id: "groceries",
            name: "Market",
            kind: .expense,
            icon: "basket",
            color: "green",
        ))
        #expect(renamed.isRenamed)
        #expect(!renamed.translatesByID)
        #expect(renamed.isDefault)
        #expect(await store.fetchCategories().first { $0.id == "groceries" } == renamed)

        // Keeping the stored name while changing only the color keeps it translating.
        let recolored = try await useCase.execute(CategoryDraft(id: "restaurants", name: "Restaurants", kind: .expense, color: "pink"))
        #expect(recolored.translatesByID)

        let back = try await useCase.execute(CategoryDraft(id: "groceries", name: "Groceries", kind: .expense))
        #expect(back.translatesByID)
    }

    @Test
    func fallbacksCanBeRenamedButNotDeleted() async throws {
        let store = InMemoryStore()
        let delete = DefaultDeleteCategoryUseCase(categories: store, transactions: store)
        for id in [TransactionCategory.otherExpenseID, TransactionCategory.otherIncomeID] {
            await #expect(throws: DomainError.fallbackCategoryCantBeDeleted(id)) {
                try await delete.execute(id: id)
            }
        }
        let renamed = try await DefaultSaveCategoryUseCase(categories: store)
            .execute(CategoryDraft(id: TransactionCategory.otherExpenseID, name: "Misc", kind: .expense))
        #expect(renamed.isFallback)
        #expect(renamed.isRenamed)
    }

    @Test
    func deletingADefaultMovesItsMovementsAndItStaysDeleted() async throws {
        let expense = try #require(sample.transactions.first { $0.kind == .expense })
        let store = InMemoryStore(transactions: [expense.with(categoryID: "groceries")])
        try await DefaultDeleteCategoryUseCase(categories: store, transactions: store).execute(id: "groceries")
        let listed = try await DefaultGetCategoriesUseCase(categories: store).execute()
        #expect(!listed.contains { $0.id == "groceries" })
        #expect(await store.fetchTransactions(in: nil).map(\.categoryID) == [TransactionCategory.otherExpenseID])
        // The name is free again.
        _ = try await DefaultSaveCategoryUseCase(categories: store).execute(CategoryDraft(name: "Groceries", kind: .expense))
    }

    @Test
    func deletingACategoryKeepsItsMovementsTagsAndRecurringRule() async throws {
        let expense = try #require(sample.transactions.first { $0.kind == .expense })
        let ruleID = UUID()
        let tagged = Transaction(
            id: expense.id, date: expense.date, status: expense.status, description: expense.description,
            kind: expense.kind, categoryID: "groceries", amount: expense.amount, currency: expense.currency,
            accountID: expense.accountID, cardID: expense.cardID, exchangeRate: expense.exchangeRate,
            note: "Weekly", recurringID: ruleID, tags: ["boda"],
        )
        let store = InMemoryStore(transactions: [tagged])
        try await DefaultDeleteCategoryUseCase(categories: store, transactions: store).execute(id: "groceries")
        let moved = try #require(await store.fetchTransactions(in: nil).first)
        #expect(moved.categoryID == TransactionCategory.otherExpenseID)
        #expect(moved.tags == ["boda"])
        #expect(moved.recurringID == ruleID)
        #expect(moved.note == "Weekly")
    }

    @Test
    func restoringBringsBackDeletedDefaultsAndUndoesEditsButKeepsYours() async throws {
        let store = InMemoryStore()
        let save = DefaultSaveCategoryUseCase(categories: store)
        let boat = try await save.execute(CategoryDraft(name: "Boat", kind: .expense))
        _ = try await save.execute(CategoryDraft(id: "transport", name: "Car", kind: .expense, icon: "car", color: "blue"))
        try await DefaultDeleteCategoryUseCase(categories: store, transactions: store).execute(id: "groceries")
        try await DefaultReorderCategoriesUseCase(categories: store).execute(ids: [boat.id])

        try await DefaultRestoreDefaultCategoriesUseCase(categories: store).execute()

        let listed = try await DefaultGetCategoriesUseCase(categories: store).execute()
        let expense = listed.filter { $0.kind == .expense }
        #expect(expense.filter(\.isDefault) == TransactionCategory.defaultExpense)
        #expect(expense.suffix(2).map(\.id) == [boat.id, TransactionCategory.otherExpenseID])
    }

    @Test
    func aBudgetIsKeptForExpensesDroppedForIncomeAndMustBePositive() async throws {
        let useCase = DefaultSaveCategoryUseCase(categories: InMemoryStore())
        let budget = Money(Decimal(string: "300.50") ?? 0, "USD")
        let boat = try await useCase.execute(CategoryDraft(name: "Boat", kind: .expense, monthlyBudget: budget))
        #expect(boat.monthlyBudget == budget)
        let tips = try await useCase.execute(CategoryDraft(name: "Tips", kind: .income, monthlyBudget: budget))
        #expect(tips.monthlyBudget == nil)
        await #expect(throws: DomainError.invalidAmount) {
            try await useCase.execute(CategoryDraft(name: "Kayak", kind: .expense, monthlyBudget: Money(0, "USD")))
        }
        await #expect(throws: DomainError.invalidAmount) {
            try await useCase.execute(CategoryDraft(name: "Kayak", kind: .expense, monthlyBudget: Money(-5, "USD")))
        }
        let cleared = try await useCase.execute(CategoryDraft(id: boat.id, name: "Boat", kind: .expense))
        #expect(cleared.monthlyBudget == nil)
    }

    @Test
    func restoringDefaultsBringsThemBackWithoutBudgets() async throws {
        let store = InMemoryStore()
        let useCase = DefaultSaveCategoryUseCase(categories: store)
        _ = try await useCase.execute(CategoryDraft(id: "groceries", name: "Groceries", kind: .expense, monthlyBudget: Money(200, "USD")))
        try await DefaultRestoreDefaultCategoriesUseCase(categories: store).execute()
        #expect(await store.fetchCategories().first { $0.id == "groceries" }?.monthlyBudget == nil)
    }

    @Test
    func reorderingKeepsTheNewOrder() async throws {
        let store = InMemoryStore()
        try await DefaultReorderCategoriesUseCase(categories: store).execute(ids: ["taxes", "groceries"])
        let listed = try await DefaultGetCategoriesUseCase(categories: store).execute()
        #expect(listed.prefix(2).map(\.id) == ["taxes", "groceries"])
    }

    @Test
    func oldBackupsDecodeWithoutTheRenamedFlag() throws {
        let json = Data(#"{"id":"groceries","name":"Groceries","kind":"expense"}"#.utf8)
        let decoded = try JSONDecoder().decode(TransactionCategory.self, from: json)
        #expect(decoded == TransactionCategory(id: "groceries", name: "Groceries", kind: .expense))
    }

    @Test
    func categoriesWithoutABudgetDecodeAsBefore() throws {
        let json = Data(#"{"id":"groceries","name":"Groceries","kind":"expense","isRenamed":false}"#.utf8)
        #expect(try JSONDecoder().decode(TransactionCategory.self, from: json).monthlyBudget == nil)
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
    func afterAPullRecordsOnADeletedCategoryMoveToOtherOfTheirKind() async throws {
        let expense = try #require(sample.transactions.first { $0.kind == .expense })
        let income = try #require(sample.transactions.first { $0.kind == .income })
        let rule = try #require(sample.recurringRules.first { $0.kind == .expense })
        let kept = UUID()
        let unknown = UUID()
        let store = InMemoryStore(
            transactions: [
                expense.with(categoryID: "custom-boat"),
                income.with(categoryID: "custom-bonus"),
                Transaction(
                    id: kept, date: expense.date, description: "Kept", kind: .expense, categoryID: "groceries",
                    amount: expense.amount, currency: expense.currency, accountID: expense.accountID,
                    exchangeRate: expense.exchangeRate,
                ),
                Transaction(
                    id: unknown, date: expense.date, description: "Not pulled yet", kind: .expense,
                    categoryID: "custom-not-pulled-yet", amount: expense.amount, currency: expense.currency,
                    accountID: expense.accountID, exchangeRate: expense.exchangeRate,
                ),
            ],
            recurringRules: [rule.with(categoryID: "custom-boat")],
        )
        let moved = try await DefaultReassignDeletedCategoriesUseCase(transactions: store, recurringRules: store)
            .execute(deletedCategoryIDs: ["custom-boat", "custom-bonus"])
        #expect(moved == 3)
        let byID = await Dictionary(uniqueKeysWithValues: store.fetchTransactions(in: nil).map { ($0.id, $0.categoryID) })
        #expect(byID[expense.id] == TransactionCategory.otherExpenseID)
        #expect(byID[income.id] == TransactionCategory.otherIncomeID)
        #expect(byID[kept] == "groceries")
        #expect(byID[unknown] == "custom-not-pulled-yet")
        #expect(await store.fetchRecurringRules().first { $0.id == rule.id }?.categoryID == TransactionCategory.otherExpenseID)
    }

    @Test
    func theRepairAfterAPullMovesNothingWhenNothingPointsAtADeletedCategory() async throws {
        let expense = try #require(sample.transactions.first { $0.kind == .expense })
        let store = InMemoryStore(transactions: [expense.with(categoryID: "groceries")])
        let repair = DefaultReassignDeletedCategoriesUseCase(transactions: store, recurringRules: store)
        #expect(try await repair.execute(deletedCategoryIDs: ["custom-boat"]) == 0)
        #expect(try await repair.execute(deletedCategoryIDs: []) == 0)
        #expect(await store.fetchTransactions(in: nil).map(\.categoryID) == ["groceries"])
    }

    @Test
    func listingReturnsThePickerOrder() async throws {
        let boat = TransactionCategory(id: "custom-boat", name: "Boat", kind: .expense)
        let store = InMemoryStore(categories: [boat] + TransactionCategory.defaults)
        let listed = try await DefaultGetCategoriesUseCase(categories: store).execute()
        let expense = listed.filter { $0.kind == .expense }.map(\.id)
        #expect(expense.first == boat.id)
        #expect(expense.last == TransactionCategory.otherExpenseID)
    }
}
