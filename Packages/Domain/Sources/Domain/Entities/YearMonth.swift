import Foundation

/// A calendar month without a time zone. Turning it into instants needs a `Calendar`, which callers
/// inject, so "October" means the person's October and not UTC's.
public struct YearMonth: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
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

    /// Half-open `[first day 00:00, first day of next month 00:00)`.
    public func dateInterval(in calendar: Calendar) -> DateInterval? {
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let end = calendar.date(byAdding: .month, value: 1, to: start)
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    public func adding(months: Int) -> Self {
        let index = year * 12 + (month - 1) + months
        // Floor division, so negative offsets wrap into the previous year correctly.
        let (quotient, remainder) = index.quotientAndRemainder(dividingBy: 12)
        let newYear = remainder < 0 ? quotient - 1 : quotient
        return Self(validYear: newYear, month: remainder < 0 ? remainder + 13 : remainder + 1)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    public var description: String {
        String(format: "%04d-%02d", year, month)
    }
}
