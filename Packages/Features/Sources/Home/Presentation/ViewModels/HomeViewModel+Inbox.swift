import DesignSystem
import Domain
import Foundation
import HomeDomain
import SharedPresentation

/// One line of the in-app notifications list.
public struct InboxItem: Identifiable, Equatable {
    public enum Tone: Equatable {
        case pending
        case accent
        case negative
    }

    /// Where tapping the item leads; the root decides how each one is shown.
    public enum Destination: Equatable {
        case transaction(id: UUID)
        case creditCard(accountID: UUID)
        /// A plastic's account, whatever its kind: the root picks the matching screen.
        case account(id: UUID)
        case debts
        case recurring
        /// Budgets are read from the month's summary.
        case summary

        public init(_ target: LedgerNotification.Target) {
            switch target {
            case let .transaction(id): self = .transaction(id: id)
            case let .creditCard(accountID): self = .creditCard(accountID: accountID)
            case let .account(id): self = .account(id: id)
            case .debts: self = .debts
            case .recurring: self = .recurring
            case .summary: self = .summary
            }
        }
    }

    /// The notification's shared id (`payment:<account>:2026-11-15`).
    public let id: String
    public let kind: LedgerNotification.Kind
    /// The day it begins to apply; it groups the list.
    public let date: Date
    public let isRead: Bool
    public let icon: KWIcon
    /// Set on budget rows, which show their category's symbol instead of `icon`.
    public let category: TransactionCategory?
    public let tone: Tone
    public let title: String
    public let body: String
    /// Whether `body` carries amounts, which "hide balances" must cover; the title stays.
    public let bodyHasAmounts: Bool
    public let destination: Destination?
    /// Set on an assistant's proposal, which waits for "Confirm" or "Discard".
    public let proposal: RecurringRule?
}

/// The notifications of one day.
public struct InboxSection: Identifiable, Equatable {
    public var id: Date {
        day
    }

    public let day: Date
    /// "Today", "Yesterday" or the date.
    public let title: String
    public let items: [InboxItem]
}

/// What the notifications screen shows: `ledgerNotifications` minus what was deleted, with the
/// read state alongside. Drafts are left out: home already lists them under "Drafts".
extension HomeViewModel {
    /// Everything that applies on the day of `now` and hasn't been deleted, newest first.
    public func inbox(now: Date = .now, calendar: Calendar = .current) -> [InboxItem] {
        guard let overview, let display else { return [] }
        return LedgerNotifications.applying(on: now, in: overview, calendar: calendar).compactMap { notification in
            guard notification.kind != .planned, notificationStates[notification.id]?.isDismissed != true else { return nil }
            return item(for: notification, overview: overview, display: display)
        }
    }

    /// What the bell shows: the unread ones.
    public func inboxCount(now: Date = .now) -> Int {
        inbox(now: now, calendar: calendar).count { !$0.isRead }
    }

    /// The assistant's proposals on top, then one section per day, newest first.
    public func inboxSections(now: Date = .now, calendar: Calendar = .current) -> (proposals: [InboxItem], days: [InboxSection]) {
        let items = inbox(now: now, calendar: calendar)
        let grouped = Dictionary(grouping: items.filter { $0.kind != .proposal }) { $0.date }
        let days = grouped.keys.sorted(by: >).map { day in
            InboxSection(day: day, title: dayTitle(day, now: now, calendar: calendar), items: grouped[day] ?? [])
        }
        return (items.filter { $0.kind == .proposal }, days)
    }

    private func dayTitle(_ day: Date, now: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        if day >= today {
            return String(localized: "Today", bundle: #bundle)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), day >= yesterday {
            return String(localized: "Yesterday", bundle: #bundle)
        }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: today)
        return sameYear
            ? day.formatted(.dateTime.weekday(.wide).day().month(.wide))
            : day.formatted(.dateTime.day().month(.wide).year())
    }

    func item(for notification: LedgerNotification, overview: HomeOverview, display: TransactionDisplay) -> InboxItem? {
        guard let content = content(of: notification, overview: overview, display: display) else { return nil }
        var proposal: RecurringRule?
        if case let .proposal(rule) = notification.subject {
            proposal = rule
        }
        return InboxItem(
            id: notification.id,
            kind: notification.kind,
            date: notification.date,
            isRead: notificationStates[notification.id]?.isRead == true,
            icon: content.icon,
            category: content.category,
            tone: content.tone,
            title: content.title,
            body: content.body,
            bodyHasAmounts: content.bodyHasAmounts,
            destination: InboxItem.Destination(notification.target),
            proposal: proposal,
        )
    }

    /// The icon and words of a notification, shared by the inbox and the notifications the system
    /// shows, so both say the same thing. `nil` when what it points at is gone.
    struct NotificationContent {
        let icon: KWIcon
        let category: TransactionCategory?
        let tone: InboxItem.Tone
        let title: String
        let body: String
        let bodyHasAmounts: Bool
    }

    // swiftlint:disable:next function_body_length
    func content(of notification: LedgerNotification, overview: HomeOverview, display: TransactionDisplay) -> NotificationContent? {
        switch notification.subject {
        case let .planned(transaction):
            let amount = formatter.string(from: transaction.amount, currencyCode: transaction.currency)
            let method = display.methodName(of: transaction)
            return NotificationContent(
                icon: .calendarCheck, category: nil, tone: .pending,
                title: String(localized: "Draft for today", bundle: #bundle),
                body: String(localized: "\(transaction.description) · \(amount) from \(method). Has it been paid?", bundle: #bundle),
                bodyHasAmounts: true,
            )
        case let .payment(accountID, dueDay, _, daysLeft):
            guard let account = overview.accounts.first(where: { $0.id == accountID }) else { return nil }
            let wording = paymentWording(account, dueDay: dueDay, days: daysLeft, in: overview)
            return NotificationContent(
                icon: .creditCard, category: nil, tone: .negative, title: wording.title, body: wording.body, bodyHasAmounts: false,
            )
        case let .cutoff(accountID):
            guard let account = overview.accounts.first(where: { $0.id == accountID }) else { return nil }
            let wording = cutoffWording(account, in: overview)
            return NotificationContent(
                icon: .clock, category: nil, tone: .accent, title: wording.title, body: wording.body, bodyHasAmounts: false,
            )
        case let .installment(loanID, number, daysLeft):
            guard let loan = overview.loans.first(where: { $0.loan.id == loanID })?.loan else { return nil }
            let wording = installmentWording(loan, number: number, days: daysLeft)
            return NotificationContent(
                icon: .cash, category: nil, tone: .pending, title: wording.title, body: wording.body, bodyHasAmounts: true,
            )
        case let .renewal(occurrence):
            let wording = renewalWording(occurrence, display: display)
            return NotificationContent(
                icon: .subscription, category: nil, tone: .accent, title: wording.title, body: wording.body, bodyHasAmounts: true,
            )
        case let .expiry(cardID):
            guard let card = overview.cards.first(where: { $0.id == cardID }) else { return nil }
            let wording = expiryWording(card, in: overview)
            return NotificationContent(
                icon: .creditCard, category: nil, tone: .pending, title: wording.title, body: wording.body, bodyHasAmounts: false,
            )
        case let .budget(categoryID, _):
            guard let alert = budgetAlerts.first(where: { $0.categoryID == categoryID }) else { return nil }
            return NotificationContent(
                icon: .chartBars, category: alert.category, tone: alert.level == .exceeded ? .negative : .pending,
                title: alert.title, body: alert.body, bodyHasAmounts: true,
            )
        case let .price(increase):
            guard let alert = priceIncreaseAlerts.first(where: { $0.increase.transactionID == increase.transactionID }) else { return nil }
            return NotificationContent(
                icon: .subscription, category: nil, tone: .pending, title: alert.title, body: alert.body, bodyHasAmounts: true,
            )
        case let .proposal(rule):
            return NotificationContent(
                icon: .sparkles, category: nil, tone: .accent, title: rule.name,
                body: proposalSubtitle(rule, hidden: false), bodyHasAmounts: true,
            )
        }
    }
}
