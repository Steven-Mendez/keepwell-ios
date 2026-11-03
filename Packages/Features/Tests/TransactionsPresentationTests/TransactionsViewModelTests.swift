import Domain
import Foundation
import Testing
@testable import TransactionsDomain
@testable import TransactionsPresentation

private struct StubSummary: GetMonthlySummaryUseCase {
    var error: DomainError?

    func execute(month: YearMonth, currency: String) async throws(DomainError) -> MonthlySummary {
        if let error {
            throw error
        }
        return MonthlySummary(
            month: month,
            currency: currency,
            totalIncome: 10,
            totalExpense: 4,
            netBalance: 6,
            savingsRate: Decimal(string: "0.6"),
        )
    }
}

private struct StubTransactions: GetMonthlyTransactionsUseCase {
    let transactions: [Transaction]

    func execute(month _: YearMonth) async throws(DomainError) -> [Transaction] {
        transactions
    }
}

private actor SpyDelete: DeleteTransactionUseCase {
    private(set) var deleted: [UUID] = []
    func execute(id: UUID) async throws(DomainError) {
        deleted.append(id)
    }
}

@Suite("TransactionsViewModel")
@MainActor
struct TransactionsViewModelTests {
    private let march = YearMonth(year: 2026, month: 3) ?? YearMonth(containing: .now, calendar: .current)
    private let nioExpense = Transaction(
        amount: 100,
        currency: "NIO",
        kind: .expense,
        category: TransactionCategory(id: "groceries", name: "Supermercado", kind: .expense),
        date: .now,
    )

    private func makeSUT(summaryError: DomainError? = nil, delete: SpyDelete = SpyDelete()) -> TransactionsViewModel {
        TransactionsViewModel(
            getMonthlySummary: StubSummary(error: summaryError),
            getMonthlyTransactions: StubTransactions(transactions: [nioExpense]),
            deleteTransaction: delete,
            month: march,
            currency: "USD",
        )
    }

    @Test
    func loadPublishesSummaryAndTransactions() async {
        let sut = makeSUT()

        await sut.load()

        #expect(sut.state == .loaded)
        #expect(sut.summary?.netBalance == 6)
        #expect(sut.transactions == [nioExpense])
        #expect(sut.availableCurrencies == ["NIO", "USD"])
    }

    @Test
    func loadFailureExposesDomainError() async {
        let sut = makeSUT(summaryError: .persistence("x"))

        await sut.load()

        #expect(sut.state == .failed(.persistence("x")))
    }

    @Test
    func monthNavigationReloadsSummaryForThatMonth() async {
        let sut = makeSUT()

        await sut.showNextMonth()
        #expect(sut.summary?.month == YearMonth(year: 2026, month: 4))

        await sut.showPreviousMonth()
        await sut.showPreviousMonth()
        #expect(sut.summary?.month == YearMonth(year: 2026, month: 2))
    }

    @Test
    func deleteCallsUseCase() async {
        let spy = SpyDelete()
        let sut = makeSUT(delete: spy)

        await sut.delete(nioExpense)

        #expect(await spy.deleted == [nioExpense.id])
        #expect(sut.actionError == nil)
    }
}
