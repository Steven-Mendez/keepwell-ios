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
        let expected = SpendingHistory.averageMonthlyExpense(transactions: sample.transactions, calendar: .current)
        #expect(result.averageExpense == expected)
        #expect(result.averageIncome != nil)
    }

    @Test
    func incomeCategoriesShareTheMonthsIncome() async throws {
        let current = try #require(try await report().months.last)
        let total = current.incomeCategories.reduce(Decimal(0)) { $0 + $1.amount }
        #expect(total == current.income)
    }
}
