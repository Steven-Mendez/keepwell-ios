import Domain
import Foundation

/// What applies on a given day, from the ledger a `HomeOverview` already holds. One function for
/// the inbox and for the native notifications, a line by line port of `ledgerNotifications` in
/// keepwell-web (`lib/domain/notifications.ts`), so ids and applicability agree on every device.
public enum LedgerNotifications {
    /// The hour a notification arrives on its day.
    public static let reminderHour = 9
    /// How far ahead local notifications are planned: two months, so a card expiring next month or
    /// the one after still gets its notification when the app is rarely opened.
    public static let scheduleDays = 62

    /// `2026-11-15`, in `calendar`'s days: the same occurrence gets the same id on every device.
    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func monthKey(_ month: YearMonth) -> String {
        String(format: "%04d-%02d", month.year, month.month)
    }

    static func lower(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }

    /// Everything that applies on the day of `now`, newest first. Planned drafts are included; the
    /// inbox leaves them out because home lists them.
    public static func applying(on now: Date, in overview: HomeOverview, calendar: Calendar) -> [LedgerNotification] {
        let found = drafts(in: overview, now: now, calendar: calendar)
            + cards(in: overview, now: now, calendar: calendar)
            + installments(in: overview, now: now, calendar: calendar)
            + renewals(in: overview, now: now, calendar: calendar)
            + expiries(in: overview, now: now, calendar: calendar)
            + budgets(in: overview, now: now, month: YearMonth(containing: now, calendar: calendar), calendar: calendar)
            + priceIncreases(in: overview, calendar: calendar)
            + proposals(in: overview, calendar: calendar)
        // Newest first; a stable order within a day keeps the list from shuffling between loads.
        return found.enumerated()
            .sorted { ($0.element.date, $1.offset) > ($1.element.date, $0.offset) }
            .map(\.element)
    }

    /// Drafts dated today or before.
    private static func drafts(in overview: HomeOverview, now: Date, calendar: Calendar) -> [LedgerNotification] {
        let today = calendar.startOfDay(for: now)
        return overview.planned.compactMap { transaction in
            let day = calendar.startOfDay(for: transaction.date)
            guard day <= today else { return nil }
            return LedgerNotification(
                id: "planned:\(lower(transaction.id))", subject: .planned(transaction), date: day, target: .transaction(transaction.id),
            )
        }
    }

    /// Credit cards: the payment from the reminder window through its due day, and the statement
    /// closing today.
    private static func cards(in overview: HomeOverview, now: Date, calendar: Calendar) -> [LedgerNotification] {
        let today = calendar.startOfDay(for: now)
        let window = overview.paymentReminderDaysBefore
        var found: [LedgerNotification] = []
        for account in overview.accounts where account.kind == .credit {
            if let dueDay = account.creditTerms?.dueDay,
               let due = BillingCycle.nextOccurrence(ofDay: dueDay, onOrAfter: now, calendar: calendar),
               let daysLeft = days(from: today, to: due, calendar: calendar),
               daysLeft <= window
            {
                found.append(LedgerNotification(
                    id: "payment:\(lower(account.id)):\(dayKey(due, calendar: calendar))",
                    subject: .payment(accountID: account.id, dueDay: dueDay, due: due, daysLeft: daysLeft),
                    date: calendar.date(byAdding: .day, value: -window, to: due) ?? due,
                    target: .creditCard(accountID: account.id),
                ))
            }
            if let cutoffDay = account.creditTerms?.cutoffDay,
               BillingCycle.nextOccurrence(ofDay: cutoffDay, onOrAfter: now, calendar: calendar) == today
            {
                found.append(LedgerNotification(
                    id: "cutoff:\(lower(account.id)):\(dayKey(today, calendar: calendar))",
                    subject: .cutoff(accountID: account.id),
                    date: today,
                    target: .creditCard(accountID: account.id),
                ))
            }
        }
        return found
    }

    /// Each loan's next installment, from the reminder window through its due day. An overdue one is
    /// Debts' to show, not a reminder's.
    private static func installments(in overview: HomeOverview, now: Date, calendar: Calendar) -> [LedgerNotification] {
        let today = calendar.startOfDay(for: now)
        let window = overview.paymentReminderDaysBefore
        return overview.loans.compactMap { progress in
            guard let next = progress.next,
                  let daysLeft = days(from: today, to: next.dueDate, calendar: calendar),
                  (0 ... window).contains(daysLeft)
            else { return nil }
            return LedgerNotification(
                id: "installment:\(lower(progress.loan.id)):\(next.number)",
                subject: .installment(loanID: progress.loan.id, number: next.number, daysLeft: daysLeft),
                date: calendar.date(byAdding: .day, value: -window, to: calendar.startOfDay(for: next.dueDate)) ?? today,
                target: .debts,
            )
        }
    }

    /// Subscriptions renewing tomorrow.
    private static func renewals(in overview: HomeOverview, now: Date, calendar: Calendar) -> [LedgerNotification] {
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }
        return overview.upcoming.compactMap { occurrence in
            guard occurrence.rule.isSubscription, calendar.startOfDay(for: occurrence.date) == tomorrow else { return nil }
            return LedgerNotification(
                id: "renewal:\(lower(occurrence.rule.id)):\(dayKey(occurrence.date, calendar: calendar))",
                subject: .renewal(occurrence),
                date: today,
                target: .recurring,
            )
        }
    }

    /// Plastics expiring this month.
    private static func expiries(in overview: HomeOverview, now: Date, calendar: Calendar) -> [LedgerNotification] {
        let month = YearMonth(containing: now, calendar: calendar)
        return overview.cards.compactMap { card in
            guard let expiry = card.expiry, expiry.year == month.year, expiry.month == month.month else { return nil }
            return LedgerNotification(
                id: "expiry:\(lower(card.id)):\(monthKey(month))",
                subject: .expiry(cardID: card.id),
                date: calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1)) ?? calendar.startOfDay(for: now),
                target: .account(id: card.accountID),
            )
        }
    }

    /// Subscriptions whose latest charge cost more than the one before.
    private static func priceIncreases(in overview: HomeOverview, calendar: Calendar) -> [LedgerNotification] {
        overview.priceIncreases.map { increase in
            LedgerNotification(
                id: "price:\(lower(increase.transactionID))",
                subject: .price(increase),
                date: calendar.startOfDay(for: increase.date),
                target: .recurring,
            )
        }
    }

    /// Recurring payments an assistant proposed, paused until confirmed.
    private static func proposals(in overview: HomeOverview, calendar: Calendar) -> [LedgerNotification] {
        overview.proposedRules.map { rule in
            LedgerNotification(
                id: "proposal:\(lower(rule.id))",
                subject: .proposal(rule),
                date: calendar.startOfDay(for: rule.startDate),
                target: .recurring,
            )
        }
    }

    /// One per budgeted category past 80% this month, with its level in the id: going over after
    /// being close is a new notification, even if the "close" one was deleted. Dated the day of the
    /// latest spending in the category, the closest the ledger knows to when the line was crossed.
    private static func budgets(in overview: HomeOverview, now: Date, month: YearMonth, calendar: Calendar) -> [LedgerNotification] {
        // An overview loaded last month must not warn about last month's spending as if it were now's.
        guard overview.month.month == month else { return [] }
        return overview.budgets.compactMap { status in
            guard status.level != .onTrack else { return nil }
            let latest = overview.latestExpenseDays[status.categoryID]
            return LedgerNotification(
                id: "budget:\(status.categoryID):\(monthKey(month)):\(status.level == .exceeded ? "over" : "near")",
                subject: .budget(categoryID: status.categoryID, level: status.level),
                date: calendar.startOfDay(for: latest ?? now),
                target: .summary,
            )
        }
    }

    private static func days(from: Date, to: Date, calendar: Calendar) -> Int? {
        calendar.dateComponents([.day], from: from, to: calendar.startOfDay(for: to)).day
    }

    /// Local notifications for the next `days` days: each id once, at the first `reminderHour` that
    /// is still ahead of `now` on a day it applies, worded for that day ("payment in 1 day"). One
    /// shots (budgets, price increases, proposals) that already apply come at `now`, and the app
    /// decides how soon.
    public static func schedule(
        from now: Date,
        in overview: HomeOverview,
        calendar: Calendar,
        days: Int = scheduleDays,
    ) -> [ScheduledNotification] {
        var seen = Set<String>()
        var scheduled: [ScheduledNotification] = []
        let today = calendar.startOfDay(for: now)
        for offset in 0 ..< days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let morning = calendar.date(bySettingHour: reminderHour, minute: 0, second: 0, of: day)
            else { continue }
            let moment = offset == 0 ? now : (calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? morning)
            for notification in applying(on: moment, in: overview, calendar: calendar) where !seen.contains(notification.id) {
                if notification.isOneShot {
                    // Only what already applies: a later day's one shot isn't known yet.
                    guard offset == 0 else { continue }
                    seen.insert(notification.id)
                    scheduled.append(ScheduledNotification(notification: notification, fireDate: now))
                } else if morning > now {
                    seen.insert(notification.id)
                    scheduled.append(ScheduledNotification(notification: notification, fireDate: morning))
                }
            }
        }
        return scheduled.sorted { $0.fireDate < $1.fireDate }
    }
}
