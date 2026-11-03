import Foundation
import Testing
@testable import Domain

@Suite("Billing cycle and additional cards")
struct BillingCycleTests {
    private let calendar = Fixtures.calendar

    @Test
    func cycleRunsFromDayAfterCutoffThroughCutoff() throws {
        let cycle = try #require(BillingCycle.cycle(containing: Fixtures.date(2026, 10, 2), cutoffDay: 28, calendar: calendar))
        #expect(cycle.start == calendar.startOfDay(for: Fixtures.date(2026, 9, 29)))
        #expect(cycle.end == calendar.startOfDay(for: Fixtures.date(2026, 10, 29)))
    }

    @Test
    func dateAfterCutoffBelongsToNextCycle() throws {
        let cycle = try #require(BillingCycle.cycle(containing: Fixtures.date(2026, 10, 29), cutoffDay: 28, calendar: calendar))
        #expect(cycle.start == calendar.startOfDay(for: Fixtures.date(2026, 10, 29)))
        #expect(cycle.end == calendar.startOfDay(for: Fixtures.date(2026, 11, 29)))
    }

    @Test
    func cutoffDayClampsToShortMonths() throws {
        let cycle = try #require(BillingCycle.cycle(containing: Fixtures.date(2026, 2, 20), cutoffDay: 31, calendar: calendar))
        #expect(cycle.start == calendar.startOfDay(for: Fixtures.date(2026, 2, 1)))
        #expect(cycle.end == calendar.startOfDay(for: Fixtures.date(2026, 3, 1)))
    }

    @Test
    func noCutoffMeansCalendarMonth() throws {
        let cycle = try #require(BillingCycle.cycle(containing: Fixtures.date(2026, 10, 15), cutoffDay: nil, calendar: calendar))
        #expect(cycle.start == calendar.startOfDay(for: Fixtures.date(2026, 10, 1)))
    }

    @Test
    func nextOccurrenceRollsToNextMonth() {
        #expect(BillingCycle.nextOccurrence(ofDay: 15, onOrAfter: Fixtures.date(2026, 10, 15), calendar: calendar)
            == calendar.startOfDay(for: Fixtures.date(2026, 10, 15)))
        #expect(BillingCycle.nextOccurrence(ofDay: 15, onOrAfter: Fixtures.date(2026, 10, 16), calendar: calendar)
            == calendar.startOfDay(for: Fixtures.date(2026, 11, 15)))
    }

    @Test
    func additionalCardUsageAgainstCap() throws {
        let card = try Card(
            accountID: UUID(),
            kind: .creditAdditional,
            lastFour: "0000",
            additional: AdditionalCardControls(holderName: "Familiar", cycleCap: Money(4000, "NIO")),
        )
        let cycle = try #require(BillingCycle.cycle(containing: Fixtures.date(2026, 10, 10), cutoffDay: 28, calendar: calendar))
        let usage = AdditionalCardUsage(
            card: card,
            transactions: [
                Fixtures.transaction(.expense, amount: "2150", currency: "NIO", card: card.id, date: Fixtures.date(2026, 10, 3)),
                Fixtures.transaction(.expense, amount: "500", currency: "NIO", card: card.id, status: .planned),
                Fixtures.transaction(.expense, amount: "999", currency: "NIO", card: card.id, date: Fixtures.date(2026, 9, 2)),
                Fixtures.transaction(.expense, amount: "100", currency: "NIO", date: Fixtures.date(2026, 10, 3)),
            ],
            cycle: cycle,
            fallbackCurrency: "USD",
        )
        #expect(usage.spent == Money(2150, "NIO"))
        #expect(usage.remaining == Money(1850, "NIO"))
        #expect(usage.fraction.map { ($0 * 100).rounded(scale: 0) } == 54)
        #expect(!usage.hasReached(Fixtures.decimal("0.8")))
        #expect(usage.hasReached(Fixtures.decimal("0.5")))
    }

    @Test
    func usageWithoutCapHasNoFraction() throws {
        let card = try Card(accountID: UUID(), kind: .creditAdditional, additional: AdditionalCardControls(holderName: "A"))
        let cycle = DateInterval(start: .distantPast, end: .distantFuture)
        let usage = AdditionalCardUsage(card: card, transactions: [], cycle: cycle, fallbackCurrency: "USD")
        #expect(usage.fraction == nil)
        #expect(usage.remaining == nil)
        #expect(usage.spent == Money(0, "USD"))
    }
}
