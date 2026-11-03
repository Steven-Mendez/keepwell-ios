import Foundation

/// A calendar month without a time zone. Turning it into instants needs a `Calendar`, which callers
/// inject, so "March" means the user's March and not UTC's.
public struct YearMonth: Hashable, Sendable, CustomStringConvertible {
    public let year: Int
    /// 1...12
    public let month: Int

    public init?(year: Int, month: Int) {
        guard (1 ... 12).contains(month) else { return nil }
        self.init(validYear: year, month: month)
    }

    public init(containing date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month], from: date)
        self.init(validYear: components.year ?? 1970, month: components.month ?? 1)
    }

    private init(validYear year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    /// Half-open `[first day 00:00, first day of next month 00:00)`; filter with `>= start && < end`.
    public func dateInterval(in calendar: Calendar) -> DateInterval? {
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let end = calendar.date(byAdding: .month, value: 1, to: start)
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    public func adding(months: Int) -> Self {
        let index = year * 12 + (month - 1) + months
        var newYear = index / 12
        var newMonthIndex = index % 12
        if newMonthIndex < 0 {
            newMonthIndex += 12
            newYear -= 1
        }
        return Self(validYear: newYear, month: newMonthIndex + 1)
    }

    public var description: String {
        String(format: "%04d-%02d", year, month)
    }
}
