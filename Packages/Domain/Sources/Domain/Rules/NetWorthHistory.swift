import Foundation

/// Net worth at the end of each of the last months, oldest first: how it moved month by month.
/// The web app computes it the same way (`netWorthHistory`), over the same shared fixture.
public enum NetWorthHistory {
    /// The current month and the eleven before it.
    public static let monthCount = 12

    public struct Point: Hashable, Sendable {
        public let month: YearMonth
        /// In the principal currency; credit debts count negative, as in today's net worth.
        public let total: Money

        public init(month: YearMonth, total: Money) {
            self.month = month
            self.total = total
        }
    }

    /// - Each past month is valued at its last moment; the current one as of the end of today, so
    ///   movements dated later this month are not counted yet.
    /// - An account adds its balance (`Balances.balance`, confirmed movements dated up to then) only
    ///   once its opening day has come; before that it contributes nothing.
    /// - Each month converts at the rate it had then: the one stored by the latest confirmed
    ///   movement dated before its cutoff whose rate is between today's principal and second
    ///   currencies (`rate(for:settings:)`). Without such a movement it falls back to today's
    ///   settings rate, which is also what months in a single currency use.
    /// - Months before the first account opened are left out; without accounts there are none.
    public static func points(
        accounts: [Account],
        transactions: [Transaction],
        settings: CurrencySettings,
        now: Date,
        calendar: Calendar,
        monthCount: Int = monthCount,
    ) throws(DomainError) -> [Point] {
        guard let firstOpening = accounts.map(\.openingDate).min() else { return [] }
        let first = YearMonth(containing: firstOpening, calendar: calendar)
        let current = YearMonth(containing: now, calendar: calendar)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let confirmed = transactions.filter(\.isConfirmed)

        var points: [Point] = []
        for offset in (0 ..< monthCount).reversed() {
            let month = current.adding(months: -offset)
            guard month >= first, let interval = month.dateInterval(in: calendar) else { continue }
            // Exclusive: the instant right after the moment the month is valued at.
            let cutoff = month == current ? endOfToday : interval.end
            try points.append(Point(
                month: month,
                total: total(accounts: accounts, transactions: confirmed, settings: settings, before: cutoff, calendar: calendar),
            ))
        }
        return points
    }

    /// The latest month against the first one shown; `nil` with fewer than two months.
    public static func change(of points: [Point]) -> Decimal? {
        guard points.count >= 2, let first = points.first, let last = points.last else { return nil }
        return last.total.amount - first.total.amount
    }

    private static func total(
        accounts: [Account],
        transactions: [Transaction],
        settings: CurrencySettings,
        before cutoff: Date,
        calendar: Calendar,
    ) throws(DomainError) -> Money {
        let movements = transactions.filter { $0.date < cutoff }
        let balances = accounts
            .filter { calendar.startOfDay(for: $0.openingDate) < cutoff }
            .flatMap { Balances.balance(of: $0, transactions: movements, calendar: calendar) }
        let monthSettings = try CurrencySettings(
            principal: settings.principal,
            second: settings.second,
            rate: rate(for: movements, settings: settings),
        )
        return try NetWorth.total(of: balances, settings: monthSettings)
    }

    /// The rate stored by the latest of `movements` (already confirmed and dated before the cutoff)
    /// that converts between today's two currencies; today's settings rate when none does. A rate
    /// for another pair (single-currency, or from before the currencies were changed) says nothing
    /// about this one.
    private static func rate(for movements: [Transaction], settings: CurrencySettings) -> Decimal {
        guard let second = settings.second else { return settings.rate }
        // The first of equally dated movements wins, as on the web.
        var latest: Transaction?
        for movement in movements {
            let rate = movement.exchangeRate
            guard rate.principal == settings.principal, rate.second == second else { continue }
            if let current = latest, movement.date <= current.date {
                continue
            }
            latest = movement
        }
        return latest?.exchangeRate.rate ?? settings.rate
    }
}
