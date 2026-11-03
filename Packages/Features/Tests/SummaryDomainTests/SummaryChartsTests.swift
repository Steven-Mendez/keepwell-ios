import Domain
import Foundation
import Testing
@testable import SummaryDomain

@Suite("Summary charts")
struct SummaryChartsTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private static let account = UUID()

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }

    private static func month(_ year: Int, _ month: Int) throws -> YearMonth {
        try #require(YearMonth(year: year, month: month))
    }

    private static func transaction(
        _ kind: TransactionKind,
        _ amount: Decimal,
        on date: Date = date(2026, 11, 2),
        category: String? = "food",
        currency: String = "USD",
        rate: ExchangeRate = .single("USD"),
        status: TransactionStatus = .confirmed,
    ) -> Transaction {
        Transaction(
            date: date,
            status: status,
            description: "",
            kind: kind,
            categoryID: kind == .transfer ? nil : category,
            amount: amount,
            currency: currency,
            accountID: account,
            exchangeRate: rate,
        )
    }

    private static func summary(_ transactions: [Transaction], month: YearMonth) -> MonthlySummary {
        MonthlySummary(month: month, transactions: transactions, currency: "USD", calendar: calendar)
    }

    // MARK: Outcome

    @Test
    func outcomeSaysSavedOverspentEvenOrNothing() throws {
        let november = try Self.month(2026, 11)
        let saved = Self.summary([Self.transaction(.income, 100), Self.transaction(.expense, 40)], month: november)
        let overspent = Self.summary([Self.transaction(.income, 10), Self.transaction(.expense, 25)], month: november)
        let noIncome = Self.summary([Self.transaction(.expense, Decimal(string: "2.73") ?? 0)], month: november)
        let even = Self.summary([Self.transaction(.income, 30), Self.transaction(.expense, 30)], month: november)
        #expect(saved.outcome == .saved(60))
        #expect(overspent.outcome == .overspent(15))
        #expect(noIncome.outcome == .overspent(Decimal(string: "2.73") ?? 0))
        #expect(even.outcome == .even)
        #expect(Self.summary([], month: november).outcome == .noActivity)
    }

    @Test
    func trendAddsTheWindowAndCountsMonths() throws {
        let november = try Self.month(2026, 11)
        let october = try Self.month(2026, 10)
        let september = try Self.month(2026, 9)
        let transactions = [
            Self.transaction(.income, 100, on: Self.date(2026, 10, 1)),
            Self.transaction(.expense, 30, on: Self.date(2026, 10, 5)),
            Self.transaction(.expense, 50, on: Self.date(2026, 11, 2)),
        ]
        let trend = CashFlowTrend(months: [september, october, november].map { Self.summary(transactions, month: $0) })
        #expect(trend.income == 100)
        #expect(trend.expense == 80)
        #expect(trend.outcome == .saved(20))
        #expect(trend.savingsRate == Decimal(string: "0.2"))
        #expect(trend.monthsSaved == 1)
        #expect(trend.monthsOverspent == 1)
    }

    @Test
    func trendWithoutIncomeHasNoRate() {
        let trend = CashFlowTrend(months: [])
        #expect(trend.savingsRate == nil)
        #expect(trend.outcome == .noActivity)
    }

    // MARK: Category breakdown

    private static func totals(_ amounts: [Decimal]) -> [MonthlySummary.CategoryTotal] {
        let month = (try? Self.month(2026, 11)) ?? YearMonth(containing: .now, calendar: calendar)
        let transactions = amounts.enumerated().map { index, amount in
            Self.transaction(.expense, amount, category: "c\(index)")
        }
        return summary(transactions, month: month).categories
    }

    @Test
    func breakdownKeepsFewCategoriesByName() {
        let breakdown = CategoryBreakdown(totals: Self.totals([60, 40]))
        #expect(breakdown.total == 100)
        #expect(breakdown.entries.map(\.slice) == [.category("c0"), .category("c1")])
        #expect(breakdown.entries.map(\.share) == [Decimal(string: "0.6"), Decimal(string: "0.4")])
    }

    @Test
    func breakdownFoldsTheLongTailIntoOneSlice() {
        let breakdown = CategoryBreakdown(totals: Self.totals([50, 40, 30, 20, 10, 5, 3, 2]))
        #expect(breakdown.entries.count == 6)
        #expect(breakdown.entries.last?.slice == .others(count: 3))
        #expect(breakdown.entries.last?.amount == 10)
        #expect(breakdown.entries.reduce(Decimal(0)) { $0 + $1.amount } == breakdown.total)
    }

    @Test
    func breakdownNeverFoldsASingleCategory() {
        let breakdown = CategoryBreakdown(totals: Self.totals([50, 40, 30, 20, 10, 5]))
        #expect(breakdown.entries.count == 6)
        #expect(!breakdown.entries.contains {
            if case .others = $0.slice {
                true
            } else {
                false
            }
        })
    }

    @Test
    func emptyBreakdown() {
        let breakdown = CategoryBreakdown(totals: [])
        #expect(breakdown.isEmpty)
        #expect(breakdown.total == 0)
    }

    // MARK: Spending pace

    @Test
    func paceRunsThroughTodayAndComparesTheSameDay() throws {
        let transactions = [
            Self.transaction(.expense, 10, on: Self.date(2026, 10, 1)),
            Self.transaction(.expense, 20, on: Self.date(2026, 10, 3)),
            Self.transaction(.expense, 70, on: Self.date(2026, 10, 20)),
            Self.transaction(.expense, 5, on: Self.date(2026, 11, 1)),
            Self.transaction(.expense, 15, on: Self.date(2026, 11, 2)),
            Self.transaction(.income, 999, on: Self.date(2026, 11, 2)),
            Self.transaction(.expense, 40, on: Self.date(2026, 11, 2), status: .planned),
        ]
        let pace = try SpendingPace(
            month: Self.month(2026, 11),
            transactions: transactions,
            calendar: Self.calendar,
            now: Self.date(2026, 11, 3),
        )
        #expect(pace.current.map(\.day) == [1, 2, 3])
        #expect(pace.current.map(\.cumulative) == [5, 20, 20])
        #expect(pace.previous.count == 31)
        #expect(pace.comparisonDay == 3)
        #expect(pace.spentSoFar == 20)
        #expect(pace.previousBySameDay == 30)
        #expect(pace.previousTotal == 100)
        #expect(pace.difference == -10)
    }

    @Test
    func pastMonthsRunToTheirLastDayAndShorterMonthsCompareAtTheirEnd() throws {
        let transactions = [
            Self.transaction(.expense, 28, on: Self.date(2026, 2, 28)),
            Self.transaction(.expense, 31, on: Self.date(2026, 3, 31)),
        ]
        let pace = try SpendingPace(
            month: Self.month(2026, 3),
            transactions: transactions,
            calendar: Self.calendar,
            now: Self.date(2026, 11, 3),
        )
        #expect(pace.current.count == 31)
        #expect(pace.previous.count == 28)
        #expect(pace.previousBySameDay == 28)
        #expect(pace.difference == 3)
    }

    @Test
    func paceUsesThePrincipalAmountOfSecondCurrencySpending() throws {
        let rate = try ExchangeRate(principal: "USD", second: "NIO", rate: Decimal(string: "36.5") ?? 1)
        let transactions = [Self.transaction(.expense, 365, on: Self.date(2026, 11, 1), currency: "NIO", rate: rate)]
        let pace = try SpendingPace(
            month: Self.month(2026, 11),
            transactions: transactions,
            calendar: Self.calendar,
            now: Self.date(2026, 11, 1),
        )
        #expect(pace.spentSoFar == 10)
    }

    // MARK: Report

    @Test
    func reportAlignsBreakdownsAndPacesWithItsMonths() {
        let transactions = [
            Self.transaction(.income, 100, on: Self.date(2026, 11, 1), category: "salary"),
            Self.transaction(.expense, 40, on: Self.date(2026, 11, 2)),
        ]
        let report = DefaultGetSummaryReportUseCase.report(
            transactions: transactions,
            categories: [],
            currency: "USD",
            calendar: Self.calendar,
            now: Self.date(2026, 11, 3),
        )
        #expect(report.expenseBreakdowns.count == report.months.count)
        #expect(report.incomeBreakdowns.count == report.months.count)
        #expect(report.paces.map(\.month) == report.months.map(\.month))
        #expect(report.expenseBreakdowns.last?.entries.first?.slice == .category("food"))
        #expect(report.incomeBreakdowns.last?.total == 100)
        #expect(report.cashFlow.outcome == .saved(60))
    }
}
