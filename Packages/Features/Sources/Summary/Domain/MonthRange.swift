import Domain
import Foundation

/// Inclusive on both ends; `start` never comes after `end`. Mirrors the web `MonthRange`.
public struct MonthRange: Hashable, Sendable {
    public let start: YearMonth
    public let end: YearMonth

    /// The two months in either order: picking the end first is still a valid range.
    public init(_ first: YearMonth, _ second: YearMonth) {
        start = min(first, second)
        end = max(first, second)
    }

    public var length: Int {
        (end.year - start.year) * 12 + (end.month - start.month) + 1
    }

    public var months: [YearMonth] {
        (0 ..< length).map { start.adding(months: $0) }
    }

    public func shifted(by months: Int) -> Self {
        Self(start.adding(months: months), end.adding(months: months))
    }

    /// What a period is measured against. Up to a year: the same months one year earlier, so
    /// December is compared with a December and seasons don't read as trends. Longer: the stretch
    /// of the same length right before it, since shifting by a year would overlap the period.
    public var comparisonShift: Int {
        length <= 12 ? 12 : length
    }

    /// January through the running month.
    public static func yearToDate(now: Date, calendar: Calendar) -> Self {
        let current = YearMonth(containing: now, calendar: calendar)
        return Self(current.adding(months: -(current.month - 1)), current)
    }

    /// `count` months ending with the running one.
    public static func lastMonths(_ count: Int, now: Date, calendar: Calendar) -> Self {
        let current = YearMonth(containing: now, calendar: calendar)
        return Self(current.adding(months: -(count - 1)), current)
    }

    /// January through December of the year `month` is in.
    static func calendarYear(containing month: YearMonth) -> Self {
        let january = month.adding(months: -(month.month - 1))
        return Self(january, january.adding(months: 11))
    }
}

/// How much of the ledger Summary reads: one month with its stepper, or a span read as one period.
public enum SummaryPeriod: Hashable, Sendable, CaseIterable {
    case month
    case thisYear
    case last12
    case custom

    /// `nil` for `.month`, which the stepper drives. Custom falls back to the last six months until
    /// the person picks both ends.
    public func range(custom: MonthRange?, now: Date, calendar: Calendar) -> MonthRange? {
        switch self {
        case .month: nil
        case .thisYear: .yearToDate(now: now, calendar: calendar)
        case .last12: .lastMonths(12, now: now, calendar: calendar)
        case .custom: custom ?? .lastMonths(6, now: now, calendar: calendar)
        }
    }
}
