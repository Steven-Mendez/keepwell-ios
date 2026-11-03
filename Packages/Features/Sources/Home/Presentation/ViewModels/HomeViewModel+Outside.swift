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
        /// An additional card that reached its alert threshold this cycle.
        case cap(UUID)
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
            ? String(localized: "spent · \(plannedCount) planned", bundle: #bundle)
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

    /// Planned movements on their day, card payments ahead of time and additional cards near
    /// their cap. Only what's still ahead is returned.
    public func reminders(now: Date = .now, calendar: Calendar = .current) -> [Reminder] {
        guard let overview, let display else { return [] }
        return plannedReminders(overview, display: display, now: now, calendar: calendar)
            + paymentReminders(overview, now: now, calendar: calendar)
            + capReminders(overview, now: now)
    }

    private func plannedReminders(_ overview: HomeOverview, display: TransactionDisplay, now: Date, calendar: Calendar) -> [Reminder] {
        overview.planned.compactMap { transaction in
            guard let date = morning(of: transaction.date, calendar: calendar), date > now else { return nil }
            let amount = formatter.string(from: transaction.amount, currencyCode: transaction.currency)
            let method = display.methodName(of: transaction)
            return Reminder(
                id: "planned-\(transaction.id)",
                kind: .planned(transaction.id),
                title: String(localized: "Planned for today", bundle: #bundle),
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
            let holder = overview.cards.first { $0.accountID == account.id && $0.kind == .creditHolder }
            let name = holder.map(CardDisplay.shortName(of:)) ?? CardDisplay.name(of: account)
            return Reminder(
                id: "payment-\(account.id)-\(Int(reminder.due.timeIntervalSince1970))",
                kind: .payment(account.id),
                title: String(localized: "\(name): payment in \(days) days", bundle: #bundle),
                body: String(localized: "Pay before day \(dueDay) so it doesn't generate interest.", bundle: #bundle),
                date: reminder.date,
            )
        }
    }

    private func capReminders(_ overview: HomeOverview, now: Date) -> [Reminder] {
        overview.additionalCards.compactMap { status in
            guard status.card.additional?.alertNearCap == true,
                  status.card.additional?.isFrozen == false,
                  status.usage.hasReached(overview.capAlertThreshold),
                  let cap = status.usage.cap
            else { return nil }
            let holder = status.card.additional?.holderName ?? ""
            let percent = formatter.number(overview.capAlertThreshold * 100, fractionDigits: 0)
            let spent = formatter.string(status.usage.spent, fractionDigits: 0)
            let capText = formatter.string(cap, fractionDigits: 0)
            return Reminder(
                // One per card and spending level, so it fires once rather than on every refresh.
                id: "cap-\(status.card.id)-\(capText)-\(percent)",
                kind: .cap(status.card.id),
                title: String(localized: "\(holder) reached \(percent)% of the cap", bundle: #bundle),
                body: String(localized: "\(spent) of \(capText) this cycle.", bundle: #bundle),
                date: now.addingTimeInterval(5),
            )
        }
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
