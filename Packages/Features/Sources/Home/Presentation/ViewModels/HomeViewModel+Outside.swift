import Core
import Domain
import Foundation
import HomeDomain
import SharedPresentation

/// A local notification the app should have scheduled, worded and timed here so the app layer
/// only hands it to the system.
public struct Reminder: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// A planned movement on its day; the notification offers to confirm it.
        case planned(UUID)
        /// A credit card's payment coming up.
        case payment(UUID)
        /// A credit card's statement closing.
        case cutoff(UUID)
        /// A plastic expiring this month.
        case cardExpiry(UUID)
        /// A subscription renewing tomorrow, by its recurring rule.
        case subscription(UUID)
        /// A category close to or over its monthly budget, by category id. Sent once: unlike the
        /// others it reports something that already happened, so rescheduling must not repeat it.
        case budget(String)
        /// A subscription charged more than the time before, by the charge. Sent once, like budgets.
        case priceIncrease(UUID)
    }

    /// Stable per occurrence, so rescheduling replaces instead of duplicating.
    public let id: String
    public let kind: Kind
    public let title: String
    public let body: String
    public let date: Date

    /// The same reminder at another time (postponing, or debug runs that show it right away).
    public func at(_ newDate: Date) -> Self {
        Self(id: id, kind: kind, title: title, body: body, date: newDate)
    }
}

/// What home shares outside the app: the widgets' snapshot and the reminders.
extension HomeViewModel {
    /// The hour reminders arrive on their day.
    static let reminderHour = 9

    public var widgetSnapshot: WidgetSnapshot? {
        guard let overview else { return nil }
        let month = overview.month
        let plannedCount = overview.plannedSummary.count
        let spentCaption = plannedCount > 0
            ? String(localized: "spent · \(plannedCount) drafts", bundle: #bundle)
            : String(localized: "spent", bundle: #bundle)
        let savedCaption = savedBadge(overview).map { "\(monthName(month.month).localizedCapitalized): \($0)" }
        return WidgetSnapshot(
            monthTitle: monthName(month.month).localizedCapitalized,
            spent: money(month.expense, overview),
            spentCaption: spentCaption,
            spentFraction: month.income > 0 ? NSDecimalNumber(decimal: min(month.expense / month.income, 1)).doubleValue : 0,
            netWorthTitle: String(localized: "Net worth", bundle: #bundle),
            netWorth: formatter.string(overview.netWorth),
            netWorthCaption: savedCaption,
            balances: overview.balances.prefix(3).map { line in
                WidgetSnapshot.Line(
                    title: line.account.bank ?? line.account.name,
                    value: formatter.string(line.balance, fractionDigits: 0),
                )
            },
            shortcutsTitle: String(localized: "Log quickly", bundle: #bundle),
            shortcuts: overview.frequentExpenseCategoryIDs.compactMap { id in
                overview.categories.first { $0.id == id }.map {
                    WidgetSnapshot.Shortcut(categoryID: id, title: CategoryDisplay.name(of: $0))
                }
            },
            updatedAt: .now,
        )
    }

    /// Planned movements on their day, card payments ahead of time, statement cutoffs on their day,
    /// plastics in their expiry month, and budgets near or over their line and subscriptions that
    /// went up in price right away. Only what's still ahead is returned.
    public func reminders(now: Date = .now, calendar: Calendar = .current) -> [Reminder] {
        guard let overview, let display else { return [] }
        return plannedReminders(overview, display: display, now: now, calendar: calendar)
            + paymentReminders(overview, now: now, calendar: calendar)
            + cutoffReminders(overview, now: now, calendar: calendar)
            + expiryReminders(overview, now: now, calendar: calendar)
            + renewalReminders(overview, display: display, now: now, calendar: calendar)
            + budgetReminders(overview, now: now, calendar: calendar)
            + priceIncreaseReminders(now: now)
    }

    /// The morning before each subscription renews, so there's time to cancel it.
    private func renewalReminders(_ overview: HomeOverview, display: TransactionDisplay, now: Date, calendar: Calendar) -> [Reminder] {
        overview.upcoming.compactMap { occurrence in
            let rule = occurrence.rule
            guard rule.isSubscription,
                  let dayBefore = calendar.date(byAdding: .day, value: -1, to: occurrence.date),
                  let date = morning(of: dayBefore, calendar: calendar),
                  date > now
            else { return nil }
            let amount = formatter.string(from: rule.amount, currencyCode: rule.currency)
            let method = display.methodName(of: RecurringSchedule.movement(
                from: rule,
                on: occurrence.date,
                exchangeRate: .single(rule.currency),
            ))
            return Reminder(
                id: "renewal-\(rule.id)-\(Int(occurrence.date.timeIntervalSince1970))",
                kind: .subscription(rule.id),
                title: String(localized: "\(rule.name) renews tomorrow", bundle: #bundle),
                body: String(localized: "\(amount) on \(method)", bundle: #bundle),
                date: date,
            )
        }
    }

    private func plannedReminders(_ overview: HomeOverview, display: TransactionDisplay, now: Date, calendar: Calendar) -> [Reminder] {
        overview.planned.compactMap { transaction in
            guard let date = morning(of: transaction.date, calendar: calendar), date > now else { return nil }
            let amount = formatter.string(from: transaction.amount, currencyCode: transaction.currency)
            let method = display.methodName(of: transaction)
            return Reminder(
                id: "planned-\(transaction.id)",
                kind: .planned(transaction.id),
                title: String(localized: "Draft for today", bundle: #bundle),
                body: String(localized: "\(transaction.description) · \(amount) from \(method). Has it been paid?", bundle: #bundle),
                date: date,
            )
        }
    }

    private func paymentReminders(_ overview: HomeOverview, now: Date, calendar: Calendar) -> [Reminder] {
        let days = overview.paymentReminderDaysBefore
        return overview.accounts.compactMap { account in
            guard account.kind == .credit,
                  let dueDay = account.creditTerms?.dueDay,
                  let reminder = nextPaymentReminder(dueDay: dueDay, daysBefore: days, now: now, calendar: calendar)
            else { return nil }
            let name = cardName(of: account, in: overview)
            return Reminder(
                id: "payment-\(account.id)-\(Int(reminder.due.timeIntervalSince1970))",
                kind: .payment(account.id),
                title: String(localized: "\(name): payment in \(days) days", bundle: #bundle),
                body: String(localized: "Pay before day \(dueDay) so it doesn't generate interest.", bundle: #bundle),
                date: reminder.date,
            )
        }
    }

    /// On the cutoff morning: what's bought after today goes to next month's statement.
    private func cutoffReminders(_ overview: HomeOverview, now: Date, calendar: Calendar) -> [Reminder] {
        overview.accounts.compactMap { account in
            guard account.kind == .credit,
                  let cutoffDay = account.creditTerms?.cutoffDay,
                  let date = nextMorning(onDay: cutoffDay, after: now, calendar: calendar)
            else { return nil }
            return Reminder(
                id: "cutoff-\(account.id)-\(Int(date.timeIntervalSince1970))",
                kind: .cutoff(account.id),
                title: String(localized: "\(cardName(of: account, in: overview)): statement closes today", bundle: #bundle),
                body: String(localized: "From tomorrow, purchases go to next month's statement.", bundle: #bundle),
                date: date,
            )
        }
    }

    /// On the first of the expiry month, listing what's charged to the card so it can be updated.
    private func expiryReminders(_ overview: HomeOverview, now: Date, calendar: Calendar) -> [Reminder] {
        overview.cards.compactMap { card in
            guard let expiry = card.expiry,
                  let day = expiry.reminderDay(calendar: calendar),
                  let date = morning(of: day, calendar: calendar),
                  date > now
            else { return nil }
            let name = CardDisplay.shortName(of: card)
            let services = overview.cardSubscriptions[card.id] ?? []
            let body = services.isEmpty
                ? String(localized: "Update it wherever it's saved before it stops working.", bundle: #bundle)
                : String(localized: "Update it in \(services.formatted(.list(type: .and))) before it stops working.", bundle: #bundle)
            return Reminder(
                id: "expiry-\(card.id)-\(expiry.year)-\(expiry.month)",
                kind: .cardExpiry(card.id),
                title: String(localized: "\(name) expires this month", bundle: #bundle),
                body: body,
                date: date,
            )
        }
    }

    private func cardName(of account: Account, in overview: HomeOverview) -> String {
        let holder = overview.cards.first { $0.accountID == account.id && $0.kind == .creditHolder }
        return holder.map(CardDisplay.shortName(of:)) ?? CardDisplay.name(of: account)
    }

    /// The reminder hour on the next `day` of a month that is still ahead of `now`.
    private func nextMorning(onDay day: Int, after now: Date, calendar: Calendar) -> Date? {
        var from = now
        for _ in 0 ..< 2 {
            guard let occurrence = BillingCycle.nextOccurrence(ofDay: day, onOrAfter: from, calendar: calendar),
                  let date = morning(of: occurrence, calendar: calendar)
            else { return nil }
            if date > now {
                return date
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: occurrence) else { return nil }
            from = next
        }
        return nil
    }

    private func nextPaymentReminder(dueDay: Int, daysBefore: Int, now: Date, calendar: Calendar) -> (due: Date, date: Date)? {
        var from = now
        // Two tries: this month's due date may already be too close to remind ahead of it.
        for _ in 0 ..< 2 {
            guard let due = BillingCycle.nextOccurrence(ofDay: dueDay, onOrAfter: from, calendar: calendar),
                  let remindDay = calendar.date(byAdding: .day, value: -daysBefore, to: due),
                  let date = morning(of: remindDay, calendar: calendar)
            else { return nil }
            if date > now {
                return (due, date)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: due) else { return nil }
            from = next
        }
        return nil
    }

    private func morning(of day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: Self.reminderHour, minute: 0, second: 0, of: day)
    }
}
