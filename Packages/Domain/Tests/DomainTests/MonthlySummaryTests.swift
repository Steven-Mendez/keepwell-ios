import Foundation
import Testing
@testable import Domain

@Suite("Monthly summary (rule 7)")
struct MonthlySummaryTests {
    private let october = YearMonth(year: 2026, month: 10) ?? YearMonth(containing: .now, calendar: .current)

    private func summary(_ transactions: [Transaction]) -> MonthlySummary {
        MonthlySummary(month: october, transactions: transactions, currency: "USD", calendar: Fixtures.calendar)
    }

    @Test
    func totalsIncomeExpenseSavingsAndRate() {
        let result = summary([
            Fixtures.transaction(.income, amount: "2452.24", category: "salary"),
            Fixtures.transaction(.expense, amount: "709.58", category: "tools"),
        ])
        #expect(result.income == Fixtures.decimal("2452.24"))
        #expect(result.expense == Fixtures.decimal("709.58"))
        #expect(result.savings == Fixtures.decimal("1742.66"))
        #expect(result.savingsRate.map { ($0 * 100).rounded(scale: 0) } == 71)
    }

    @Test
    func noIncomeMeansNoSavingsRate() {
        #expect(summary([Fixtures.transaction(.expense, amount: "10")]).savingsRate == nil)
    }

    @Test
    func overspendingGivesNegativeSavings() {
        let result = summary([
            Fixtures.transaction(.income, amount: "100", category: "salary"),
            Fixtures.transaction(.expense, amount: "150"),
        ])
        #expect(result.savings == -50)
        #expect(result.savingsRate == Fixtures.decimal("-0.5"))
    }

    @Test
    func plannedTransfersAndOtherMonthsAreExcluded() {
        let result = summary([
            Fixtures.transaction(.expense, amount: "3500", currency: "NIO", status: .planned),
            Fixtures.transaction(.transfer, amount: "1200", currency: "NIO", actualDebited: "33.15"),
            Fixtures.transaction(.expense, amount: "40", date: Fixtures.date(2026, 9, 30)),
            Fixtures.transaction(.expense, amount: "5", category: "education"),
        ])
        #expect(result.expense == 5)
        #expect(result.income == 0)
    }

    @Test
    func secondCurrencySpendingIsConvertedWithEachStoredRate() {
        let result = summary([Fixtures.transaction(.expense, amount: "879", currency: "NIO", actualDebited: "24.28")])
        #expect(result.expense == Fixtures.decimal("24.28"))
    }

    @Test
    func categoriesAreSortedWithShares() {
        let result = summary([
            Fixtures.transaction(.expense, amount: "25", category: "restaurants"),
            Fixtures.transaction(.expense, amount: "75", category: "tools"),
        ])
        #expect(result.categories.map(\.categoryID) == ["tools", "restaurants"])
        #expect(result.categories.map(\.share) == [Fixtures.decimal("0.75"), Fixtures.decimal("0.25")])
    }

    @Test
    func averageCountsOnlyMonthsWithSpending() {
        let average = SpendingHistory.averageMonthlyExpense(
            transactions: [
                Fixtures.transaction(.expense, amount: "47.13", date: Fixtures.date(2026, 9, 10)),
                Fixtures.transaction(.expense, amount: "709.58", date: Fixtures.date(2026, 10, 10)),
                Fixtures.transaction(.income, amount: "3.02", date: Fixtures.date(2026, 8, 10)),
            ],
            currency: "USD",
            calendar: Fixtures.calendar,
        )
        #expect(average.map { $0.rounded(scale: 2) } == Fixtures.decimal("378.36"))
    }

    @Test
    func averageIsNilWithoutSpending() {
        #expect(SpendingHistory.averageMonthlyExpense(transactions: [], currency: "USD", calendar: Fixtures.calendar) == nil)
    }

    @Test
    func monthlySeriesFillsEmptyMonthsOldestFirst() {
        let series = SpendingHistory.monthlyExpenses(
            endingAt: october,
            count: 6,
            transactions: [Fixtures.transaction(.expense, amount: "47.13", date: Fixtures.date(2026, 9, 10))],
            currency: "USD",
            calendar: Fixtures.calendar,
        )
        #expect(series.map(\.month.month) == [5, 6, 7, 8, 9, 10])
        #expect(series.map(\.expense) == [0, 0, 0, 0, Fixtures.decimal("47.13"), 0])
    }

    @Test
    func yearMonthWrapsAcrossYears() {
        let january = YearMonth(year: 2026, month: 1)
        #expect(january?.adding(months: -1) == YearMonth(year: 2025, month: 12))
        #expect(january?.adding(months: -13) == YearMonth(year: 2024, month: 12))
        #expect(january?.adding(months: 12) == YearMonth(year: 2027, month: 1))
        #expect(YearMonth(year: 2026, month: 13) == nil)
    }

    @Test
    func plannedSummaryTotalsBothCurrencies() {
        let planned = PlannedSummary(transactions: [
            Fixtures.transaction(.expense, amount: "3500", currency: "NIO", status: .planned),
            Fixtures.transaction(.expense, amount: "2000", currency: "NIO", status: .planned),
            Fixtures.transaction(.expense, amount: "1300", currency: "NIO", status: .planned),
            Fixtures.transaction(.expense, amount: "700", currency: "NIO", status: .planned),
            Fixtures.transaction(.expense, amount: "1", currency: "NIO"),
        ])
        #expect(planned.count == 4)
        #expect(planned.secondTotal == 7500)
        #expect(planned.principalTotal.rounded(scale: 2) == Fixtures.decimal("204.78"))
    }
}
