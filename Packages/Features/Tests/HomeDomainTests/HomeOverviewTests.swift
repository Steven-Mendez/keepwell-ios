import Domain
import DomainSamples
import Foundation
import Testing
@testable import HomeDomain

@Suite("Home overview")
struct HomeOverviewTests {
    private let sample = SampleData.standard

    private func overview() async throws -> HomeOverview {
        let store = InMemoryStore(sample: sample)
        return try await DefaultGetHomeOverviewUseCase(
            accounts: store, cards: store, transactions: store, categories: store, settings: store,
            now: { SampleData.defaultReferenceDate },
        ).execute()
    }

    @Test
    func plannedMovementsAreListedSoonestFirst() async throws {
        let result = try await overview()
        #expect(result.planned.count == 4)
        #expect(result.plannedSummary.count == 4)
        #expect(result.planned.map(\.date) == result.planned.map(\.date).sorted())
        #expect(result.planned.allSatisfy { !$0.isConfirmed })
    }

    @Test
    func recentMovementsAreTheLatestConfirmedOnes() async throws {
        let result = try await overview()
        let confirmed = sample.transactions.filter(\.isConfirmed)
        let expectedCount = min(DefaultGetHomeOverviewUseCase.recentCount, confirmed.count)
        let dates = result.recent.map(\.date)
        let newestFirst = dates.sorted { $0 > $1 }
        #expect(result.recent.count == expectedCount)
        let allConfirmed = result.recent.allSatisfy(\.isConfirmed)
        #expect(allConfirmed)
        #expect(dates == newestFirst)
        let newest = try #require(confirmed.map(\.date).max())
        #expect(result.recent.first?.date == newest)
    }

    @Test
    func balancesListDepositsBeforeCashAndLeaveCardsOut() async throws {
        let result = try await overview()
        #expect(result.balances.map(\.account.kind) == [.deposit, .deposit, .cash])
        #expect(result.accountCount == 3)
    }

    @Test
    func cardDebtIsTheCardsTotalInPrincipal() async throws {
        let result = try await overview()
        let debt = try #require(result.cardDebt)
        #expect(debt.currency == "USD")
        #expect(debt.amount < 0)
        let others = try result.balances.reduce(Decimal(0)) { total, line in
            try total + sample.settings.currencies.exchangeRate.convert(line.balance, to: "USD").amount
        }
        #expect(others + debt.amount == result.netWorth.amount)
    }

    @Test
    func cappedAdditionalCardsShowTheirUsage() async throws {
        let status = try #require(try await overview().additionalCards.first)
        #expect(status.card.id == SampleData.IDs.mastercardAdditional)
        #expect(status.usage.cap == Money(4000, "NIO"))
        #expect(status.holder?.id == SampleData.IDs.mastercardHolder)
    }

    @Test
    func cardCountLeavesTransferChannelsOut() async throws {
        let result = try await overview()
        #expect(result.cardCount == sample.cards.count { $0.kind != .transfer })
    }

    @Test
    func monthIsTheCurrentOne() async throws {
        let result = try await overview()
        #expect(result.month.month == YearMonth(containing: SampleData.defaultReferenceDate, calendar: .current))
    }
}
