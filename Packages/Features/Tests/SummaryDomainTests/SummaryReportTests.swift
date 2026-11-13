import Domain
import DomainSamples
import Foundation
import Testing
@testable import SummaryDomain

@Suite("Summary report")
struct SummaryReportTests {
    private let sample = SampleData.standard

    private func report() async throws -> SummaryReport {
        let store = InMemoryStore(sample: sample)
        return try await DefaultGetSummaryReportUseCase(
            transactions: store, categories: store, settings: store,
            now: { SampleData.defaultReferenceDate },
        ).execute()
    }

    @Test
    func coversSixMonthsEndingWithTheCurrentOne() async throws {
        let result = try await report()
        let current = YearMonth(containing: SampleData.defaultReferenceDate, calendar: .current)
        #expect(result.months.count == 6)
        #expect(result.months.last?.month == current)
        #expect(result.months.first?.month == current.adding(months: -5))
        #expect(result.currency == "USD")
    }

    @Test
    func netWorthEndsWithTodayWhenAccountsAreGiven() async throws {
        let store = InMemoryStore(sample: sample)
        let result = try await DefaultGetSummaryReportUseCase(
            transactions: store, categories: store, settings: store, accounts: store,
            now: { SampleData.defaultReferenceDate },
        ).execute()
        let current = YearMonth(containing: SampleData.defaultReferenceDate, calendar: .current)
        #expect(result.netWorth.last?.month == current)
        #expect(result.netWorth.allSatisfy { $0.total.currency == "USD" })
        #expect(try await report().netWorth.isEmpty)
    }

    @Test
    func eachMonthMatchesItsMonthlySummary() async throws {
        let result = try await report()
        for month in result.months {
            let expected = MonthlySummary(month: month.month, transactions: sample.transactions, currency: "USD", calendar: .current)
            #expect(month == expected)
        }
    }

    @Test
    func averagesOnlyCountMonthsWithMovements() async throws {
        let result = try await report()
        let expected = SpendingHistory.averageMonthlyExpense(transactions: sample.transactions, currency: "USD", calendar: .current)
        #expect(result.averageExpense == expected)
        #expect(result.averageIncome != nil)
    }

    @Test
    func incomeCategoriesShareTheMonthsIncome() async throws {
        let current = try #require(try await report().months.last)
        let total = current.incomeCategories.reduce(Decimal(0)) { $0 + $1.amount }
        #expect(total == current.income)
    }

    @Test
    func eachMonthCarriesItsBudgetsInTheSameOrder() async throws {
        let budgeted = sample.categories.map { category in
            category.kind == .expense
                ? TransactionCategory(id: category.id, name: category.name, kind: category.kind, monthlyBudget: Money(100, "USD"))
                : category
        }
        let result = DefaultGetSummaryReportUseCase.report(
            transactions: sample.transactions,
            categories: budgeted,
            currency: "USD",
            calendar: .current,
            now: SampleData.defaultReferenceDate,
        )
        #expect(result.budgets.count == result.months.count)
        for (month, budgets) in zip(result.months, result.budgets) {
            #expect(budgets == CategoryBudgetStatus.statuses(of: month, categories: budgeted))
            #expect(budgets.count == TransactionCategory.defaultExpense.count)
        }
        let unbudgeted = try await report()
        #expect(unbudgeted.budgets.joined().isEmpty)
        #expect(unbudgeted.otherCurrencyBudgets.isEmpty)
    }

    @Test
    func namesTheBudgetsLeftOutForBeingInAnotherCurrency() {
        let inCordobas = sample.categories.map { category in
            category.kind == .expense
                ? TransactionCategory(id: category.id, name: category.name, kind: category.kind, monthlyBudget: Money(100, "NIO"))
                : category
        }
        let result = DefaultGetSummaryReportUseCase.report(
            transactions: sample.transactions,
            categories: inCordobas,
            currency: "USD",
            calendar: .current,
            now: SampleData.defaultReferenceDate,
        )
        #expect(result.budgets.joined().isEmpty)
        #expect(result.otherCurrencyBudgets == [
            OtherCurrencyBudgets(currency: "NIO", count: TransactionCategory.defaultExpense.count),
        ])
    }
}
