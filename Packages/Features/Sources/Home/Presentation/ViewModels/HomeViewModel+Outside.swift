import Core
import Domain
import Foundation
import HomeDomain
import SharedPresentation

/// A local notification the app should have scheduled, worded and timed here so the app layer
/// only hands it to the system. Its `id` is the notification's shared id, so the inbox, the
/// server's pushes and these all name the same thing.
public struct Reminder: Hashable, Sendable {
    public let id: String
    public let kind: LedgerNotification.Kind
    /// The draft a "planned" reminder offers to confirm.
    public let transactionID: UUID?
    /// Where tapping it leads, as `NotificationTarget` JSON (the same shape a push carries).
    public let target: [String: String]
    /// Reports something that already happened: told once, right away.
    public let isOneShot: Bool
    public let title: String
    public let body: String
    public let date: Date

    /// The same reminder at another time (postponing, or debug runs that show it right away).
    public func at(_ newDate: Date) -> Self {
        Self(
            id: id, kind: kind, transactionID: transactionID, target: target, isOneShot: isOneShot,
            title: title, body: body, date: newDate,
        )
    }
}

/// What home shares outside the app: the widgets' snapshot and the reminders.
extension HomeViewModel {
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

    /// What to schedule as local notifications: each notification once, on the first morning it
    /// applies that is still ahead (see `LedgerNotifications.schedule`), minus what was read or
    /// deleted anywhere.
    public func reminders(now: Date = .now, calendar: Calendar = .current) -> [Reminder] {
        guard let overview, let display else { return [] }
        return LedgerNotifications.schedule(from: now, in: overview, calendar: calendar).compactMap { scheduled in
            let state = notificationStates[scheduled.notification.id]
            if state?.isRead == true || state?.isDismissed == true {
                return nil
            }
            return reminder(for: scheduled, overview: overview, display: display)
        }
    }

    private func reminder(for scheduled: ScheduledNotification, overview: HomeOverview, display: TransactionDisplay) -> Reminder? {
        let notification = scheduled.notification
        guard let content = content(of: notification, overview: overview, display: display) else { return nil }
        var transactionID: UUID?
        if case let .planned(transaction) = notification.subject {
            transactionID = transaction.id
        }
        return Reminder(
            id: notification.id,
            kind: notification.kind,
            transactionID: transactionID,
            target: notification.target.json,
            isOneShot: notification.isOneShot,
            title: content.title,
            body: content.body,
            date: scheduled.fireDate,
        )
    }
}
