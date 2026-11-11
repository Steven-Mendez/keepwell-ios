import Domain
import Foundation
import Testing
@testable import SummaryDomain

@Suite("Trends")
struct TrendReportTests {
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

    private static func movement(
        _ kind: TransactionKind,
        _ amount: Decimal,
        _ date: Date,
        category: String = "food",
        status: TransactionStatus = .confirmed,
    ) -> Transaction {
        Transaction(
            date: date, status: status, description: "", kind: kind,
            categoryID: kind == .transfer ? nil : category, amount: amount, currency: "USD",
            accountID: account, exchangeRate: .single("USD"),
        )
    }

    private static func expense(_ amount: Decimal, _ date: Date, _ category: String = "food") -> Transaction {
        movement(.expense, amount, date, category: category)
    }

    private static func income(_ amount: Decimal, _ date: Date) -> Transaction {
        movement(.income, amount, date, category: "salary")
    }

    private static func report(_ transactions: [Transaction], _ range: MonthRange, now: Date) -> TrendReport {
        TrendReport(transactions: transactions, currency: "USD", requested: range, now: now, calendar: calendar)
    }

    @Test
    func buildsRangesInEitherOrderAndCountsTheirMonths() throws {
        let range = try MonthRange(Self.month(2026, 8), Self.month(2026, 3))
        let now = Self.date(2026, 11, 5)
        #expect(try range.start == (Self.month(2026, 3)))
        #expect(range.length == 6)
        #expect(MonthRange.lastMonths(12, now: now, calendar: Self.calendar).length == 12)
        let ytd = MonthRange.yearToDate(now: now, calendar: Self.calendar)
        #expect(try ytd.start == (Self.month(2026, 1)))
        #expect(try ytd.end == (Self.month(2026, 11)))
    }

    @Test
    func comparesUpToAYearWithTheSameMonthsAYearEarlierAndLongerSpansWithTheStretchBefore() throws {
        #expect(try MonthRange(Self.month(2026, 3), Self.month(2026, 5)).comparisonShift == 12)
        #expect(try MonthRange(Self.month(2025, 1), Self.month(2026, 6)).comparisonShift == 18)
    }

    @Test
    func addsUpThePeriodAndFindsBestAndWorstMonthsAndRunningSavings() throws {
        let result = try Self.report(
            [
                Self.income(1000, Self.date(2026, 1, 10)), Self.expense(400, Self.date(2026, 1, 12)),
                Self.income(1000, Self.date(2026, 2, 10)), Self.expense(1300, Self.date(2026, 2, 12)),
                Self.expense(100, Self.date(2026, 3, 2)),
            ],
            MonthRange(Self.month(2026, 1), Self.month(2026, 4)),
            now: Self.date(2026, 12, 31),
        )
        #expect(result.months.count == 4)
        #expect(result.cashFlow.income == 2000)
        #expect(result.cashFlow.expense == 1800)
        #expect(try result.bestMonth?.month == (Self.month(2026, 1)))
        #expect(try result.worstMonth?.month == (Self.month(2026, 2)))
        #expect(result.cumulativeSavings == [600, 300, 200, 200])
        #expect(result.averageExpense == 600)
        #expect(!result.hasComparison)
        #expect(result.biggestIncrease == nil)
        #expect(result.activeMonthCount == 3)
    }

    @Test
    func ranksCategoriesAndSaysWhichGrewAndWhichDroppedAgainstLastYear() throws {
        let result = try Self.report(
            [
                Self.expense(300, Self.date(2026, 3, 5), "food"),
                Self.expense(50, Self.date(2026, 3, 6), "transport"),
                Self.expense(100, Self.date(2025, 3, 5), "food"),
                Self.expense(200, Self.date(2025, 3, 6), "transport"),
                Self.expense(80, Self.date(2025, 3, 7), "gym"),
            ],
            MonthRange(Self.month(2026, 3), Self.month(2026, 3)),
            now: Self.date(2026, 12, 1),
        )
        #expect(result.hasComparison)
        #expect(result.expenseCategories.map(\.categoryID) == ["food", "transport", "gym"])
        #expect(result.expenseCategories.first?.changeRate == 2)
        #expect(result.biggestIncrease?.categoryID == "food")
        #expect(result.biggestDecrease?.categoryID == "transport")
        // The ring only holds what was spent in this period.
        #expect(result.expenseBreakdown.entries.count == 2)
        #expect(result.expenseBreakdown.total == 350)
        #expect(result.categoryTrends.first?.amounts == [300])
        #expect(result.categoryTrends.count == 2)
    }

    @Test
    func stopsAtTheRunningMonthAndComparesItWithLastYearOnlyUpToTheSameDay() throws {
        let result = try Self.report(
            [
                Self.expense(10, Self.date(2026, 11, 3)),
                Self.expense(20, Self.date(2025, 11, 4)),
                Self.expense(999, Self.date(2025, 11, 20)),
            ],
            MonthRange(Self.month(2026, 10), Self.month(2027, 2)),
            now: Self.date(2026, 11, 5),
        )
        #expect(try result.range.end == (Self.month(2026, 11)))
        #expect(result.isRunning)
        #expect(result.comparisonMonths.last?.expense == 20)
    }

    @Test
    func ignoresPlannedMovementsAndTransfers() throws {
        let result = try Self.report(
            [
                Self.movement(.expense, 500, Self.date(2026, 5, 1), status: .planned),
                Self.movement(.transfer, 70, Self.date(2026, 5, 2)),
            ],
            MonthRange(Self.month(2026, 5), Self.month(2026, 5)),
            now: Self.date(2026, 12, 1),
        )
        #expect(result.cashFlow.expense == 0)
        #expect(result.bestMonth == nil)
    }

    @Test
    func totalsEveryYearFromTheFirstMovement() throws {
        let now = Self.date(2026, 11, 5)
        let transactions = [Self.income(100, Self.date(2024, 6, 1)), Self.expense(40, Self.date(2026, 2, 1))]
        #expect(try TrendReport.activityRange(of: transactions, now: now, calendar: Self.calendar)?.start == (Self.month(2024, 6)))
        let years = TrendReport.yearTotals(of: transactions, currency: "USD", now: now, calendar: Self.calendar)
        #expect(years.map(\.year) == [2024, 2025, 2026])
        #expect(years.first?.cashFlow.income == 100)
        #expect(years.last?.isRunning == true)
    }

    @Test
    func periodsResolveToTheirRanges() {
        let now = Self.date(2026, 11, 5)
        #expect(SummaryPeriod.month.range(custom: nil, now: now, calendar: Self.calendar) == nil)
        #expect(SummaryPeriod.custom.range(custom: nil, now: now, calendar: Self.calendar)?.length == 6)
        #expect(SummaryPeriod.thisYear.range(custom: nil, now: now, calendar: Self.calendar)?.length == 11)
    }
}
