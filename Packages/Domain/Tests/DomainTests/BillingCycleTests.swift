import Foundation
import Testing
@testable import Domain

@Suite("Billing cycle")
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
}
