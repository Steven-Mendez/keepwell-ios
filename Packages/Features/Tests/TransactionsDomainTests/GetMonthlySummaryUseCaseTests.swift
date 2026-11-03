import CustomDump
import Domain
import Foundation
import Testing
@testable import TransactionsDomain

@Suite("GetMonthlySummaryUseCase")
struct GetMonthlySummaryUseCaseTests {
    private func summary(of transactions: [Transaction], currency: String = "USD") async throws -> MonthlySummary {
        let repository = MockTransactionRepository(transactions: transactions)
        let sut = DefaultGetMonthlySummaryUseCase(repository: repository, calendar: Fixture.calendar)
        return try await sut.execute(month: Fixture.march2026, currency: currency)
    }

    @Test
    func sumsWithoutFloatingPointError() async throws {
        // With Double, 0.1 + 0.2 == 0.30000000000000004.
        let result = try await summary(of: [
            Fixture.transaction("0.10", .income),
            Fixture.transaction("0.20", .income),
            Fixture.transaction("0.10", .expense),
            Fixture.transaction("0.05", .expense),
        ])

        #expect(result.totalIncome == Fixture.decimal("0.3"))
        #expect(result.totalExpense == Fixture.decimal("0.15"))
        #expect(result.netBalance == Fixture.decimal("0.15"))
        #expect(result.savingsRate == Fixture.decimal("0.5"))
    }

    @Test
    func keepsPrecisionForLargeAmounts() async throws {
        let result = try await summary(of: [
            Fixture.transaction("12345678901234567.89", .income),
            Fixture.transaction("0.01", .expense),
        ])

        #expect(result.netBalance == Fixture.decimal("12345678901234567.88"))
    }

    @Test
    func computesSavingsRate() async throws {
        let result = try await summary(of: [
            Fixture.transaction("3000", .income),
            Fixture.transaction("2250", .expense),
        ])

        expectNoDifference(
            result,
            MonthlySummary(
                month: Fixture.march2026,
                currency: "USD",
                totalIncome: 3000,
                totalExpense: 2250,
                netBalance: 750,
                savingsRate: Fixture.decimal("0.25"),
            ),
        )
    }

    @Test
    func roundsSavingsRateToFourPlaces() async throws {
        let result = try await summary(of: [
            Fixture.transaction("3", .income),
            Fixture.transaction("2", .expense),
        ])

        #expect(result.savingsRate == Fixture.decimal("0.3333"))
    }

    @Test
    func savingsRateIsNegativeWhenOverspending() async throws {
        let result = try await summary(of: [
            Fixture.transaction("1000", .income),
            Fixture.transaction("1500", .expense),
        ])

        #expect(result.netBalance == -500)
        #expect(result.savingsRate == Fixture.decimal("-0.5"))
    }

    @Test
    func savingsRateIsNilWithoutIncome() async throws {
        let result = try await summary(of: [Fixture.transaction("80", .expense)])

        #expect(result.totalIncome == 0)
        #expect(result.netBalance == -80)
        #expect(result.savingsRate == nil)
    }

    @Test
    func emptyMonthIsAllZeros() async throws {
        let result = try await summary(of: [])

        #expect(result.totalIncome == 0)
        #expect(result.totalExpense == 0)
        #expect(result.netBalance == 0)
        #expect(result.savingsRate == nil)
    }

    @Test
    func ignoresPlannedTransfersOtherCurrenciesAndOtherMonths() async throws {
        let result = try await summary(of: [
            Fixture.transaction("1000", .income),
            Fixture.transaction("100", .expense),
            Fixture.transaction("500", .expense, status: .planned),
            Fixture.transaction("200", .transfer),
            Fixture.transaction("3660", .expense, currency: "NIO"),
            Fixture.transaction("10", .expense, on: Fixture.date(2026, 2, 28, hour: 23, minute: 59)),
            Fixture.transaction("10", .expense, on: Fixture.date(2026, 4, 1, hour: 0)),
        ])

        #expect(result.totalIncome == 1000)
        #expect(result.totalExpense == 100)
    }

    @Test
    func includesFirstInstantOfTheMonth() async throws {
        let result = try await summary(of: [
            Fixture.transaction("10", .expense, on: Fixture.date(2026, 3, 1, hour: 0)),
        ])

        #expect(result.totalExpense == 10)
    }

    @Test
    func summarizesTheRequestedCurrency() async throws {
        let result = try await summary(
            of: [
                Fixture.transaction("1000", .income),
                Fixture.transaction("3660", .expense, currency: "NIO"),
            ],
            currency: "NIO",
        )

        #expect(result.currency == "NIO")
        #expect(result.totalIncome == 0)
        #expect(result.totalExpense == 3660)
    }

    @Test
    func requestsTheMonthFromTheRepository() async throws {
        let repository = MockTransactionRepository()
        let sut = DefaultGetMonthlySummaryUseCase(repository: repository, calendar: Fixture.calendar)

        _ = try await sut.execute(month: Fixture.march2026, currency: "USD")

        let expected = DateInterval(start: Fixture.date(2026, 3, 1, hour: 0), end: Fixture.date(2026, 4, 1, hour: 0))
        #expect(await repository.requestedPeriods == [expected])
    }

    @Test
    func propagatesRepositoryErrors() async {
        let repository = MockTransactionRepository(error: .persistence("disk full"))
        let sut = DefaultGetMonthlySummaryUseCase(repository: repository, calendar: Fixture.calendar)

        await #expect(throws: DomainError.persistence("disk full")) {
            try await sut.execute(month: Fixture.march2026, currency: "USD")
        }
    }
}
