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

    /// The last cutoff before `due`'s day: the statement a payment due that day settles. Cutoff 20 and
    /// due day 10 pay on Nov 10 what closed on Oct 20; cutoff 5 and due day 25 pay on Nov 25 what
    /// closed on Nov 5.
    public static func statementCutoff(before due: Date, cutoffDay: Int, calendar: Calendar) -> Date? {
        let dueDay = calendar.startOfDay(for: due)
        let month = YearMonth(containing: due, calendar: calendar)
        guard let candidate = cutoff(in: month, day: cutoffDay, calendar: calendar) else { return nil }
        return candidate < dueDay ? candidate : cutoff(in: month.adding(months: -1), day: cutoffDay, calendar: calendar)
    }

    private static func cutoff(in month: YearMonth, day: Int, calendar: Calendar) -> Date? {
        guard let interval = month.dateInterval(in: calendar),
              let days = calendar.range(of: .day, in: .month, for: interval.start)
        else { return nil }
        return calendar.date(from: DateComponents(year: month.year, month: month.month, day: min(day, days.count)))
    }
}
