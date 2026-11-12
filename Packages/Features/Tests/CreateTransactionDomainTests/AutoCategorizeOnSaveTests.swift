import Domain
import DomainSamples
import Foundation
import Testing
@testable import CreateTransactionDomain

/// Saving a new movement goes through the person's categorization rules (T26); an edit never does.
/// The sample ledger has the rule "Uber → Transport".
@Suite("Categorization rules when saving")
struct AutoCategorizeOnSaveTests {
    private typealias IDs = SampleData.IDs
    private let store = InMemoryStore(sample: .standard)
    private let now = SampleData.defaultReferenceDate

    private func contextUseCase() -> DefaultGetTransactionContextUseCase {
        DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: store, rules: store,
            now: { [now] in now },
        )
    }

    private func save(_ draft: TransactionDraft) async throws -> SavedTransaction {
        try await DefaultSaveTransactionUseCase(context: contextUseCase(), transactions: store).execute(draft)
    }

    private func expense(_ description: String, category: String?, id: UUID = UUID()) -> TransactionDraft {
        TransactionDraft(
            id: id, kind: .expense, amount: 100, currency: "NIO", categoryID: category,
            source: .account(IDs.cash), description: description, date: now,
        )
    }

    @Test
    func aNewMovementWithoutACategoryTakesTheRuleOrOther() async throws {
        // What Siri saves when the person names no category and says "Uber".
        #expect(try await save(expense("Uber", category: TransactionCategory.otherExpenseID)).transaction.categoryID == "transport")
        #expect(try await save(expense("Uber home", category: nil)).transaction.categoryID == "transport")
        #expect(try await save(expense("Bakery", category: nil)).transaction.categoryID == TransactionCategory.otherExpenseID)
        #expect(try await save(expense("Uber eats", category: "restaurants")).transaction.categoryID == "restaurants")
    }

    @Test
    func anEditInOtherNeverGoesThroughTheRules() async throws {
        let id = UUID()
        let first = try await DefaultSaveTransactionUseCase(
            context: DefaultGetTransactionContextUseCase(
                settings: store, categories: store, accounts: store, cards: store, transactions: store, now: { [now] in now },
            ),
            transactions: store,
        ).execute(expense("Uber home", category: TransactionCategory.otherExpenseID, id: id))
        #expect(first.transaction.categoryID == TransactionCategory.otherExpenseID)
        var draft = expense("Uber home", category: TransactionCategory.otherExpenseID, id: id)
        draft.note = "edited"
        let edited = try await DefaultUpdateTransactionUseCase(stored: contextUseCase(), transactions: store, settings: store)
            .execute(draft)
        #expect(edited.transaction.categoryID == TransactionCategory.otherExpenseID)
    }
}
