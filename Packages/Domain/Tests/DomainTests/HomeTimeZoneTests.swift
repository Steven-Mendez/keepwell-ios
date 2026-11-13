import Foundation
import Testing
@testable import Domain

/// The home time zone (T21): the settings carry it, it is filled from the device only when missing,
/// and the rules read days in whatever calendar they're given, not the device's.
@Suite("Home time zone")
struct HomeTimeZoneTests {
    private func settings(timeZone: String? = nil, onboarded: Bool = true) -> Settings {
        Settings(currencies: .initial, hasCompletedOnboarding: onboarded, timeZone: timeZone)
    }

    @Test
    func isFilledFromTheDeviceOnlyWhenMissingAndAfterOnboarding() {
        #expect(settings().fillingMissingTimeZone("Asia/Tokyo")?.timeZone == "Asia/Tokyo")
        // A zone set elsewhere (another device, or by hand) wins.
        #expect(settings(timeZone: "Europe/Madrid").fillingMissingTimeZone("Asia/Tokyo") == nil)
        #expect(settings(onboarded: false).fillingMissingTimeZone("Asia/Tokyo") == nil)
        #expect(settings().fillingMissingTimeZone("not a zone!") == nil)
    }

    @Test
    func acceptsTheShapeOfAnIANANameOnly() {
        for name in ["America/Managua", "America/Argentina/Buenos_Aires", "Etc/GMT+6", "UTC"] {
            #expect(HomeTimeZone.isWellFormed(name), "\(name)")
        }
        for name in ["", "../etc/passwd", "not a zone!", "/Europe", String(repeating: "A", count: 65)] {
            #expect(!HomeTimeZone.isWellFormed(name), "\(name)")
        }
        #expect(HomeTimeZone.calendar("Asia/Tokyo")?.timeZone.identifier == "Asia/Tokyo")
        #expect(HomeTimeZone.calendar("Mars/Olympus") == nil)
    }

    /// The same rule as keepwell-web `tests/domain/time-zone.test.ts`: Jan 31 09:00 in Tokyo is
    /// Jan 30 18:00 in Managua, so a month later is a different instant in each calendar.
    @Test
    func addsMonthsOnTheCalendarItIsGiven() throws {
        let start = try #require(ISO8601DateFormatter().date(from: "2026-01-31T00:00:00Z"))
        let rule = RecurringRule(
            name: "Rent", kind: .expense, categoryID: "other-expense", amount: 10, currency: "USD",
            accountID: UUID(), frequency: .monthly, startDate: start,
        )
        let tokyo = try #require(HomeTimeZone.calendar("Asia/Tokyo"))
        let managua = try #require(HomeTimeZone.calendar("America/Managua"))
        let inTokyo = try #require(RecurringSchedule.occurrence(of: rule, 1, calendar: tokyo))
        #expect(inTokyo == ISO8601DateFormatter().date(from: "2026-02-28T00:00:00Z"))
        #expect(tokyo.component(.day, from: inTokyo) == 28)
        #expect(RecurringSchedule.occurrence(of: rule, 1, calendar: managua) == ISO8601DateFormatter().date(from: "2026-03-01T00:00:00Z"))
    }
}
