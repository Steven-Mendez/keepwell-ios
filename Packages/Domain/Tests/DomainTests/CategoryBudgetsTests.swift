import Foundation
import Testing
@testable import Domain

@Suite("Category budgets")
struct CategoryBudgetsTests {
    private func total(_ id: String, _ amount: String) -> MonthlySummary.CategoryTotal {
        MonthlySummary.CategoryTotal(categoryID: id, amount: Decimal(string: amount) ?? 0, share: 0)
    }

    private func expense(_ id: String, budget: String?, currency: String = "USD") -> TransactionCategory {
        TransactionCategory(
            id: id,
            name: id,
            kind: .expense,
            monthlyBudget: budget.map { Money(Decimal(string: $0) ?? 0, currency) },
        )
    }

    private func status(spent: String, budget: String) throws -> CategoryBudgetStatus {
        try #require(CategoryBudgetStatus.statuses(
            totals: [total("groceries", spent)],
            categories: [expense("groceries", budget: budget)],
            currency: "USD",
        ).first)
    }

    @Test
    func justUnderEightyPercentIsOnTrack() throws {
        let status = try status(spent: "79.99", budget: "100")
        #expect(status.ratio == Decimal(string: "0.7999"))
        #expect(status.level == .onTrack)
    }

    @Test
    func exactlyEightyPercentIsNearTheLimit() throws {
        #expect(try status(spent: "80", budget: "100").level == .nearLimit)
        #expect(try status(spent: "99.99", budget: "100").level == .nearLimit)
    }

    @Test
    func exactlyTheBudgetIsExceeded() throws {
        let status = try status(spent: "100", budget: "100")
        #expect(status.ratio == 1)
        #expect(status.level == .exceeded)
        #expect(status.remaining == 0)
        let over = try self.status(spent: "130.50", budget: "100")
        #expect(over.level == .exceeded)
        #expect(over.remaining == Decimal(string: "-30.5"))
    }

    @Test
    func onlyExpenseBudgetsInThePrincipalCurrencyCountSortedByRatio() {
        let categories = [
            expense("groceries", budget: "200"),
            expense("restaurants", budget: "50"),
            expense("travel", budget: "500"),
            expense("taxes", budget: "300", currency: "NIO"),
            expense("leisure", budget: nil),
            TransactionCategory(id: "salary", name: "Salary", kind: .income, monthlyBudget: Money(100, "USD")),
        ]
        let statuses = CategoryBudgetStatus.statuses(
            totals: [
                total("groceries", "100"),
                total("restaurants", "45"),
                total("taxes", "1000"),
                total("leisure", "70"),
                total("salary", "5000"),
            ],
            categories: categories,
            currency: "USD",
        )
        #expect(statuses.map(\.categoryID) == ["restaurants", "groceries", "travel"])
        #expect(statuses.map(\.level) == [.nearLimit, .onTrack, .onTrack])
        let travel = statuses.last
        #expect(travel?.spent == Money(0, "USD"))
        #expect(travel?.budget == Money(500, "USD"))
    }

    @Test
    func countsTheExpenseBudgetsInOtherCurrenciesPerCurrency() {
        let categories = [
            expense("groceries", budget: "200"),
            expense("taxes", budget: "300", currency: "NIO"),
            expense("rent", budget: "9000", currency: "NIO"),
            expense("travel", budget: "50", currency: "EUR"),
            expense("zero", budget: "0", currency: "NIO"),
            expense("leisure", budget: nil),
            TransactionCategory(id: "salary", name: "Salary", kind: .income, monthlyBudget: Money(100, "NIO")),
        ]
        #expect(OtherCurrencyBudgets.of(categories: categories, currency: "USD") == [
            OtherCurrencyBudgets(currency: "EUR", count: 1),
            OtherCurrencyBudgets(currency: "NIO", count: 2),
        ])
        #expect(CategoryBudgetStatus.statuses(totals: [], categories: categories, currency: "USD").map(\.categoryID) == ["groceries"])
        #expect(OtherCurrencyBudgets.of(categories: [expense("groceries", budget: "200")], currency: "USD").isEmpty)
    }

    @Test
    func readsTheMonthsConfirmedSpending() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 3)))
        let spending = Transaction(
            id: UUID(), date: date, status: .confirmed, description: "Market", kind: .expense, categoryID: "groceries",
            amount: 90, currency: "USD", accountID: UUID(), exchangeRate: .single("USD"),
        )
        let month = MonthlySummary(
            month: YearMonth(containing: date, calendar: calendar),
            transactions: [spending],
            currency: "USD",
            calendar: calendar,
        )
        let status = try #require(CategoryBudgetStatus.statuses(of: month, categories: [expense("groceries", budget: "100")]).first)
        #expect(status.spent == Money(90, "USD"))
        #expect(status.level == .nearLimit)
    }
}
