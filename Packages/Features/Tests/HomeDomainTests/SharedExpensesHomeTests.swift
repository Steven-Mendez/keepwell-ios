import Domain
import DomainSamples
import Foundation
import Testing
@testable import HomeDomain

/// Home's month, budgets (and so the budget notifications) read the ledger's debts, and the
/// deposits of deleted ones (`SharedExpenseLedger`).
@Suite("Shared expenses on home")
struct SharedExpensesHomeTests {
    private let ledger = SharedExpenseLedger()

    private func overview(_ store: InMemoryStore) async throws -> HomeOverview {
        try await DefaultGetHomeOverviewUseCase(
            accounts: store, cards: store, transactions: store, categories: store, settings: store, personalDebts: store,
            calendar: ledger.calendar, now: { [ledger] in ledger.now },
        ).execute()
    }

    @Test
    func homesMonthReadsTheLedgersDebts() async throws {
        let budgeted = TransactionCategory.defaults.map { category in
            category.id == "restaurants"
                ? TransactionCategory(id: category.id, name: category.name, kind: category.kind, monthlyBudget: Money(50, "USD"))
                : category
        }
        let store = InMemoryStore(
            accounts: [ledger.account],
            transactions: ledger.movements,
            categories: budgeted,
            personalDebts: ledger.debts,
        )
        let result = try await overview(store)
        #expect(result.month.expense == 130)
        #expect(result.month.income == 1000)
        let budget = try #require(result.budgets.first { $0.categoryID == "restaurants" })
        #expect(budget.spent.amount == 30)
        #expect(budget.level == .onTrack)
        // Balances still move by the whole movement and the deposit.
        #expect(result.netWorth == Money(800, "USD"))
    }

    @Test
    func aDeletedDebtsDepositStillIsntIncome() async throws {
        let store = InMemoryStore(accounts: [ledger.account], transactions: ledger.movements, personalDebts: ledger.debts)
        try await store.deletePersonalDebt(id: #require(ledger.debts.first?.id))
        #expect(try await overview(store).month.income == 1000)
    }
}
