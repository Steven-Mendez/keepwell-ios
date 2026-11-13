import Foundation
import Testing
@testable import Domain

/// A ledger recorded under other currencies, read after the main currency changed (swapped from
/// USD to NIO in the app, or changed to EUR elsewhere). Each movement converts with the rate it
/// stored, or is left out and counted; dollars are never labelled euros. Same cases as the web.
@Suite("Monthly summary after the main currency changes")
struct MonthlySummaryCurrencyChangeTests {
    private let october = YearMonth(year: 2026, month: 10) ?? YearMonth(containing: .now, calendar: .current)
    private let september = YearMonth(year: 2026, month: 9) ?? YearMonth(containing: .now, calendar: .current)

    private func rate(_ principal: String, _ second: String, _ value: String) throws -> ExchangeRate {
        try ExchangeRate(principal: principal, second: second, rate: Fixtures.decimal(value))
    }

    private func single(_ code: String) throws -> ExchangeRate {
        try ExchangeRate(principal: code, second: code, rate: 1)
    }

    private func summary(_ transactions: [Transaction], currency: String) -> MonthlySummary {
        MonthlySummary(month: october, transactions: transactions, currency: currency, calendar: Fixtures.calendar)
    }

    @Test
    func dollarsWithAStoredEuroRateConvertWithThatRate() throws {
        // Recorded as USD + EUR (1 USD = 0.92 EUR), then swapped so EUR is the main currency.
        let usdEur = try rate("USD", "EUR", "0.92")
        let result = summary([
            Fixtures.transaction(.expense, amount: "100", rate: usdEur),
            Fixtures.transaction(.income, amount: "50", category: "salary", rate: usdEur),
        ], currency: "EUR")
        #expect(result.expense == 92)
        #expect(result.income == 46)
        #expect(result.excluded.isEmpty)
    }

    @Test
    func dollarsWithoutAnyEuroRateAreLeftOutAndCounted() {
        // Recorded as USD + NIO; nothing stored on the movement reaches EUR.
        let result = summary([Fixtures.transaction(.expense, amount: "100", rate: Fixtures.usdNio)], currency: "EUR")
        #expect(result.expense == 0)
        #expect(result.excluded == [UnconvertedMovements(currency: "USD", count: 1)])
    }

    @Test
    func swappingToTheSecondCurrencyConvertsEachMovementWithItsRate() {
        let result = summary([
            Fixtures.transaction(.expense, amount: "100", category: "tools"),
            Fixtures.transaction(.expense, amount: "250", currency: "NIO", category: "restaurants"),
            Fixtures.transaction(.income, amount: "50", category: "salary"),
        ], currency: "NIO")
        #expect(result.expense.rounded(scale: 2) == Fixtures.decimal("3912.43"))
        #expect(result.income.rounded(scale: 2) == Fixtures.decimal("1831.22"))
        #expect(result.currency == "NIO")
        #expect(result.excluded.isEmpty)
    }

    @Test
    func convertingUsesTheRealDebit() {
        let result = summary([Fixtures.transaction(.expense, amount: "20", actualDebited: "20.42")], currency: "NIO")
        #expect(result.expense.rounded(scale: 2) == Fixtures.decimal("747.87"))
    }

    @Test
    func leavesOutByCurrencyWhatItsStoredRateCantConvert() throws {
        let result = try summary([
            Fixtures.transaction(.expense, amount: "100"),
            Fixtures.transaction(.expense, amount: "250", currency: "NIO"),
            Fixtures.transaction(.income, amount: "50", category: "salary"),
            Fixtures.transaction(.expense, amount: "9", currency: "EUR", rate: single("EUR")),
            Fixtures.transaction(.transfer, amount: "1200", currency: "NIO", actualDebited: "33.15"),
            Fixtures.transaction(.expense, amount: "7", status: .planned),
        ], currency: "EUR")
        #expect(result.expense == 9)
        #expect(result.income == 0)
        #expect(result.excluded == [
            UnconvertedMovements(currency: "NIO", count: 1),
            UnconvertedMovements(currency: "USD", count: 2),
        ])
    }

    @Test
    func monthlyTotalsAndAveragesFollowTheSameRule() throws {
        let list = try [
            Fixtures.transaction(.expense, amount: "100", date: Fixtures.date(2026, 9, 10)),
            Fixtures.transaction(.expense, amount: "9", currency: "EUR", date: Fixtures.date(2026, 9, 12), rate: single("EUR")),
        ]
        let series = SpendingHistory.monthlyTotals(
            of: .expense,
            endingAt: october,
            count: 2,
            transactions: list,
            currency: "EUR",
            calendar: Fixtures.calendar,
        )
        #expect(series.map(\.month) == [september, october])
        #expect(series.map(\.total) == [9, 0])
        #expect(SpendingHistory.averageMonthlyTotal(of: .expense, transactions: list, currency: "EUR", calendar: Fixtures.calendar) == 9)
    }

    @Test
    func storedAmountConvertsOnlyWithinTheStoredRate() throws {
        let lunch = Fixtures.transaction(.expense, amount: "250", currency: "NIO")
        #expect(lunch.storedAmount(in: "USD")?.rounded(scale: 2) == Fixtures.decimal("6.83"))
        #expect(lunch.storedAmount(in: "NIO") == 250)
        #expect(lunch.storedAmount(in: "EUR") == nil)
        #expect(try Fixtures.transaction(.expense, amount: "3", rate: single("USD")).storedAmount(in: "NIO") == nil)
    }
}
