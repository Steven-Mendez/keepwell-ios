import Foundation

/// A credit card's billing cycle: from the day after the previous cutoff through the cutoff day.
/// Cutoff days past a month's end clamp to its last day (cutoff 31 closes on Feb 28/29).
public enum BillingCycle {
    /// Half-open interval containing `date`. Without a cutoff day the cycle is the calendar month.
    public static func cycle(containing date: Date, cutoffDay: Int?, calendar: Calendar) -> DateInterval? {
        guard let cutoffDay else {
            return YearMonth(containing: date, calendar: calendar).dateInterval(in: calendar)
        }
        let month = YearMonth(containing: date, calendar: calendar)
        guard let thisCutoff = cutoff(in: month, day: cutoffDay, calendar: calendar),
              let previousCutoff = cutoff(in: month.adding(months: -1), day: cutoffDay, calendar: calendar),
              let nextCutoff = cutoff(in: month.adding(months: 1), day: cutoffDay, calendar: calendar)
        else { return nil }

        let day = calendar.startOfDay(for: date)
        let (startCutoff, endCutoff) = day <= thisCutoff ? (previousCutoff, thisCutoff) : (thisCutoff, nextCutoff)
        guard let start = calendar.date(byAdding: .day, value: 1, to: startCutoff),
              let end = calendar.date(byAdding: .day, value: 1, to: endCutoff)
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// The next date (today included) that falls on `day` of a month, clamped like cutoffs. Used for
    /// cutoff and payment reminders.
    public static func nextOccurrence(ofDay day: Int, onOrAfter date: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: date)
        let month = YearMonth(containing: date, calendar: calendar)
        guard let candidate = cutoff(in: month, day: day, calendar: calendar) else { return nil }
        return candidate >= today ? candidate : cutoff(in: month.adding(months: 1), day: day, calendar: calendar)
    }

    private static func cutoff(in month: YearMonth, day: Int, calendar: Calendar) -> Date? {
        guard let interval = month.dateInterval(in: calendar),
              let days = calendar.range(of: .day, in: .month, for: interval.start)
        else { return nil }
        return calendar.date(from: DateComponents(year: month.year, month: month.month, day: min(day, days.count)))
    }
}

/// How much an additional card has spent of its cycle cap.
public struct AdditionalCardUsage: Hashable, Sendable {
    public let spent: Money
    public let cap: Money?

    /// Confirmed purchases made with `card` inside `cycle`, expressed in the cap's currency.
    public init(card: Card, transactions: [Transaction], cycle: DateInterval, fallbackCurrency: String) {
        let currency = card.additional?.cycleCap?.currency ?? fallbackCurrency
        let total = transactions
            .filter { $0.cardID == card.id && $0.isConfirmed && $0.kind == .expense && cycle.contains($0.date) }
            .reduce(Decimal(0)) { $0 + $1.amount(in: currency) }
        spent = Money(total, currency)
        cap = card.additional?.cycleCap
    }

    /// What is left before the cap; never negative.
    public var remaining: Money? {
        cap.map { Money(max($0.amount - spent.amount, 0), $0.currency) }
    }

    /// `spent / cap`, uncapped above 1 so overspending is visible.
    public var fraction: Decimal? {
        guard let cap, cap.amount > 0 else { return nil }
        return spent.amount / cap.amount
    }

    public func hasReached(_ threshold: Decimal) -> Bool {
        (fraction ?? 0) >= threshold
    }
}
