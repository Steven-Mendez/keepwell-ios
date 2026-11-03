import Domain
import Foundation

/// Running spending through a month next to the month before, day by day. Comparing on the same
/// day of the month answers "am I on track?" mid-month, which month totals can't until it ends.
public struct SpendingPace: Hashable, Sendable {
    public struct Point: Hashable, Sendable {
        /// Day of the month, from 1.
        public let day: Int
        /// Everything spent from day 1 through `day`.
        public let cumulative: Decimal
    }

    public let month: YearMonth
    public let previousMonth: YearMonth
    /// Through today for the running month, through its last day otherwise.
    public let current: [Point]
    /// The whole previous month.
    public let previous: [Point]

    public init(month: YearMonth, transactions: [Transaction], calendar: Calendar, now: Date) {
        let previousMonth = month.adding(months: -1)
        let daysInMonth = Self.dayCount(of: month, calendar: calendar)
        let lastDay = YearMonth(containing: now, calendar: calendar) == month
            ? min(calendar.component(.day, from: now), daysInMonth)
            : daysInMonth
        self.month = month
        self.previousMonth = previousMonth
        current = Self.points(month, through: lastDay, transactions: transactions, calendar: calendar)
        previous = Self.points(
            previousMonth,
            through: Self.dayCount(of: previousMonth, calendar: calendar),
            transactions: transactions,
            calendar: calendar,
        )
    }

    /// The last day the running month has data for.
    public var comparisonDay: Int {
        current.last?.day ?? 1
    }

    public var spentSoFar: Decimal {
        current.last?.cumulative ?? 0
    }

    /// The previous month by the same day; its last day when it was shorter (March 31 vs February 28).
    public var previousBySameDay: Decimal {
        previous.last { $0.day <= comparisonDay }?.cumulative ?? 0
    }

    public var previousTotal: Decimal {
        previous.last?.cumulative ?? 0
    }

    /// Positive when spending runs ahead of last month.
    public var difference: Decimal {
        spentSoFar - previousBySameDay
    }

    private static func dayCount(of month: YearMonth, calendar: Calendar) -> Int {
        guard let start = month.dateInterval(in: calendar)?.start else { return 30 }
        return calendar.range(of: .day, in: .month, for: start)?.count ?? 30
    }

    private static func points(_ month: YearMonth, through lastDay: Int, transactions: [Transaction], calendar: Calendar) -> [Point] {
        var perDay: [Int: Decimal] = [:]
        for transaction in transactions
            where transaction.isConfirmed && transaction.kind == .expense
            && YearMonth(containing: transaction.date, calendar: calendar) == month
        {
            perDay[calendar.component(.day, from: transaction.date), default: 0] += transaction.principalAmount
        }
        var running = Decimal(0)
        return (1 ... max(lastDay, 1)).map { day in
            running += perDay[day] ?? 0
            return Point(day: day, cumulative: running)
        }
    }
}
