import Domain
import DomainSamples
import Foundation
import Testing
@testable import SummaryDomain

/// The summary, its pace, trends and year totals count only the person's part of split expenses
/// and leave repayment deposits out of income (`SharedExpenseLedger`).
@Suite("Shared expenses in the summary")
struct SharedExpensesSummaryTests {
    private let ledger = SharedExpenseLedger()

    @Test
    func theSpendingPaceAndTheSummaryReportUseThePersonsPart() {
        let pace = SpendingPace(
            month: ledger.month, transactions: ledger.movements, currency: "USD", calendar: ledger.calendar, now: ledger.now,
            debts: ledger.links,
        )
        #expect(pace.spentSoFar == 130)
        let report = DefaultGetSummaryReportUseCase.report(
            transactions: ledger.movements, categories: TransactionCategory.defaults, currency: "USD", debts: ledger.links,
            calendar: ledger.calendar, now: ledger.now,
        )
        #expect(report.months.last?.expense == 130)
        #expect(report.averageExpense == 130)
        #expect(report.averageIncome == 1000)
        #expect(report.paces.last?.spentSoFar == 130)
    }

    @Test
    func trendsAndYearTotalsUseThePersonsPart() {
        let report = TrendReport(
            transactions: ledger.movements, currency: "USD", requested: MonthRange(ledger.month, ledger.month), now: ledger.now,
            calendar: ledger.calendar, debts: ledger.links,
        )
        #expect(report.cashFlow.expense == 130)
        #expect(report.cashFlow.income == 1000)
        let years = TrendReport.yearTotals(
            of: ledger.movements,
            currency: "USD",
            now: ledger.now,
            calendar: ledger.calendar,
            debts: ledger.links,
        )
        #expect(years.first?.cashFlow.expense == 130)
    }

    @Test
    func theUseCasesReadTheDebtsAndTheDepositsOfDeletedOnes() async throws {
        let store = InMemoryStore(transactions: ledger.movements, personalDebts: ledger.debts)
        // Ana's debt deleted: her deposit still isn't income.
        try await store.deletePersonalDebt(id: #require(ledger.debts.first?.id))
        let report = try await DefaultGetSummaryReportUseCase(
            transactions: store, categories: store, settings: store, personalDebts: store, calendar: ledger.calendar,
            now: { [ledger] in ledger.now },
        ).execute()
        #expect(report.months.last?.income == 1000)
        // Without Ana's share, the dinner costs the person 60.
        #expect(report.months.last?.expense == 160)
        let range = try await DefaultGetRangeSummaryUseCase(
            transactions: store, settings: store, personalDebts: store, calendar: ledger.calendar, now: { [ledger] in ledger.now },
        ).execute(period: .custom, custom: MonthRange(ledger.month, ledger.month))
        #expect(range?.report.cashFlow.income == 1000)
        #expect(range?.report.cashFlow.expense == 160)
    }
}
