import Foundation
import Testing
@testable import Domain

/// A personal debt's optional due date (keepwell-web `tests/domain/debt-due-date.test.ts`): where it
/// stands on a day, and the order of the People list.
@Suite("Personal debt due dates")
struct DebtDueDateTests {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar
    }

    private var managua: Calendar {
        calendar("America/Managua")
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        managua.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
    }

    private func debt(
        person: String = "Ana",
        date: Date? = nil,
        due: Date? = nil,
        repaid: Decimal? = nil,
        settledAt: Date? = nil,
    ) -> PersonalDebt {
        PersonalDebt(
            person: person,
            direction: .theyOweMe,
            amount: Money(12, "USD"),
            date: date ?? self.date(2026, 9, 1),
            repayments: repaid.map { [DebtRepayment(amount: $0, date: self.date(2026, 11, 1))] } ?? [],
            settledAt: settledAt,
            dueDate: due,
        )
    }

    @Test
    func countsCalendarDaysToTheDueDateWhateverTheHour() {
        let due = debt(due: date(2026, 11, 15, hour: 0))
        #expect(due.dueStatus(today: date(2026, 11, 12, hour: 23), calendar: managua) == .upcoming(daysLeft: 3))
        #expect(due.dueStatus(today: date(2026, 11, 14, hour: 0), calendar: managua) == .upcoming(daysLeft: 1))
        #expect(due.dueStatus(today: date(2026, 11, 15, hour: 23), calendar: managua) == .today)
        #expect(due.dueStatus(today: date(2026, 11, 18, hour: 1), calendar: managua) == .overdue(daysLate: 3))
    }

    @Test
    func saysNothingWithoutADateSettledOrWithNothingLeft() {
        let today = date(2026, 11, 12)
        let due = date(2026, 11, 15, hour: 0)
        #expect(debt().dueStatus(today: today, calendar: managua) == nil)
        #expect(debt(due: due, settledAt: today).dueStatus(today: today, calendar: managua) == nil)
        #expect(debt(due: due, repaid: 12).dueStatus(today: today, calendar: managua) == nil)
    }

    @Test
    func readsTheDayInTheCalendarItIsGiven() throws {
        // Midnight of Nov 15 in Managua is 06:00 UTC; at 03:00 UTC on Nov 15 it is still the 14th there.
        let parser = ISO8601DateFormatter()
        let due = try #require(parser.date(from: "2026-11-15T06:00:00Z"))
        let now = try #require(parser.date(from: "2026-11-15T03:00:00Z"))
        #expect(debt(due: due).dueStatus(today: now, calendar: managua) == .upcoming(daysLeft: 1))
        #expect(debt(due: due).dueStatus(today: now, calendar: calendar("Europe/Madrid")) == .today)
    }

    @Test
    func datedOpenDebtsComeFirstSoonestFirstThenOpenOnesNewestFirstThenSettled() {
        let ordered = PersonalDebtOrder.ordered([
            debt(person: "No date, old", date: date(2026, 9, 1)),
            debt(person: "Due later", due: date(2026, 12, 1, hour: 0)),
            debt(person: "Settled", due: date(2026, 10, 1, hour: 0), settledAt: date(2026, 10, 2)),
            debt(person: "Overdue", due: date(2026, 10, 1, hour: 0)),
            debt(person: "No date, new", date: date(2026, 11, 1)),
        ])
        #expect(ordered.map(\.person) == ["Overdue", "Due later", "No date, new", "No date, old", "Settled"])
    }

    @Test
    func repayingAndSettlingKeepTheDueDate() throws {
        let due = date(2026, 11, 15, hour: 0)
        let repaid = try debt(due: due).repaying(5, on: date(2026, 11, 2))
        #expect(repaid.dueDate == due)
        #expect(repaid.settled(at: date(2026, 11, 3)).dueDate == due)
    }
}
