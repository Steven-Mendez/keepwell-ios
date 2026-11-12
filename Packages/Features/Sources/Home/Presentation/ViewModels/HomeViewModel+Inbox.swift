import DesignSystem
import Domain
import Foundation
import HomeDomain
import SharedPresentation

/// One line of the in-app notifications list: something that applies right now.
public struct InboxItem: Identifiable, Equatable {
    public enum Tone: Equatable {
        case pending
        case accent
        case negative
    }

    /// Where tapping the item leads; the root decides how each one is shown.
    public enum Destination: Equatable {
        case creditCard(accountID: UUID)
        /// A plastic's account, whatever its kind: the root picks the matching screen.
        case account(id: UUID)
        case debts
        case recurring
        /// Budgets are read from the month's summary.
        case summary
    }

    public let id: String
    public let icon: KWIcon
    /// Set on budget rows, which show their category's symbol instead of `icon`.
    public let category: TransactionCategory?
    public let tone: Tone
    public let title: String
    public let body: String
    /// Whether `body` carries amounts, which "hide balances" must cover; the title stays.
    public let bodyHasAmounts: Bool
    public let destination: Destination?
}

/// The notifications list: what the reminders would tell the person if they were sent this
/// instant. Nothing is stored (no read state), so an item is gone as soon as it stops applying.
/// Planned movements are left out: home already lists them under "Drafts".
extension HomeViewModel {
    /// Everything that applies on the day of `now`, most pressing payments first.
    public func inbox(now: Date = .now, calendar: Calendar = .current) -> [InboxItem] {
        guard let overview, let display else { return [] }
        return paymentItems(overview, now: now, calendar: calendar)
            + installmentItems(overview, now: now, calendar: calendar)
            + renewalItems(overview, display: display, now: now, calendar: calendar)
            + expiryItems(overview, now: now, calendar: calendar)
            + budgetItems(overview, now: now, calendar: calendar)
            + priceIncreaseItems()
    }

    /// What the bell shows: the list plus the rules an assistant proposed, which wait for an answer.
    public func inboxCount(now: Date = .now) -> Int {
        guard let overview else { return 0 }
        return inbox(now: now, calendar: calendar).count + overview.proposedRules.count
    }

    /// Credit cards' payments inside the reminder window and statements closing today.
    private func paymentItems(_ overview: HomeOverview, now: Date, calendar: Calendar) -> [InboxItem] {
        let today = calendar.startOfDay(for: now)
        return overview.accounts.filter { $0.kind == .credit }.flatMap { account -> [InboxItem] in
            var items: [InboxItem] = []
            if let dueDay = account.creditTerms?.dueDay,
               let due = BillingCycle.nextOccurrence(ofDay: dueDay, onOrAfter: now, calendar: calendar),
               let days = calendar.dateComponents([.day], from: today, to: due).day,
               days <= overview.paymentReminderDaysBefore
            {
                let wording = paymentWording(account, dueDay: dueDay, days: days, in: overview)
                items.append(InboxItem(
                    id: "payment-\(account.id)", icon: .creditCard, category: nil, tone: .negative,
                    title: wording.title, body: wording.body, bodyHasAmounts: false,
                    destination: .creditCard(accountID: account.id),
                ))
            }
            if let cutoffDay = account.creditTerms?.cutoffDay,
               BillingCycle.nextOccurrence(ofDay: cutoffDay, onOrAfter: now, calendar: calendar) == today
            {
                let wording = cutoffWording(account, in: overview)
                items.append(InboxItem(
                    id: "cutoff-\(account.id)", icon: .clock, category: nil, tone: .accent,
                    title: wording.title, body: wording.body, bodyHasAmounts: false,
                    destination: .creditCard(accountID: account.id),
                ))
            }
            return items
        }
    }

    /// Only the next installment of each loan, from the reminder day until its due day: an
    /// overdue one is shown by Debts.
    private func installmentItems(_ overview: HomeOverview, now: Date, calendar: Calendar) -> [InboxItem] {
        let today = calendar.startOfDay(for: now)
        return overview.loans.compactMap { progress in
            guard let next = progress.next,
                  let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: next.dueDate)).day,
                  (0 ... overview.paymentReminderDaysBefore).contains(days)
            else { return nil }
            let wording = installmentWording(progress.loan, next: next, days: days)
            return InboxItem(
                id: "installment-\(progress.loan.id)-\(next.number)", icon: .cash, category: nil, tone: .pending,
                title: wording.title, body: wording.body, bodyHasAmounts: true, destination: .debts,
            )
        }
    }

    private func renewalItems(_ overview: HomeOverview, display: TransactionDisplay, now: Date, calendar: Calendar) -> [InboxItem] {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return [] }
        return overview.upcoming.compactMap { occurrence in
            guard occurrence.rule.isSubscription, calendar.isDate(occurrence.date, inSameDayAs: tomorrow) else { return nil }
            let wording = renewalWording(occurrence, display: display)
            return InboxItem(
                id: "renews-\(occurrence.rule.id)", icon: .subscription, category: nil, tone: .accent,
                title: wording.title, body: wording.body, bodyHasAmounts: true, destination: .recurring,
            )
        }
    }

    private func expiryItems(_ overview: HomeOverview, now: Date, calendar: Calendar) -> [InboxItem] {
        let month = YearMonth(containing: now, calendar: calendar)
        return overview.cards.compactMap { card in
            guard let expiry = card.expiry, expiry.year == month.year, expiry.month == month.month else { return nil }
            let wording = expiryWording(card, in: overview)
            return InboxItem(
                id: "expiry-\(card.id)", icon: .creditCard, category: nil, tone: .pending,
                title: wording.title, body: wording.body, bodyHasAmounts: false, destination: .account(id: card.accountID),
            )
        }
    }

    private func budgetItems(_ overview: HomeOverview, now: Date, calendar: Calendar) -> [InboxItem] {
        // An overview loaded last month must not warn about last month's spending as if it were now's.
        guard overview.month.month == YearMonth(containing: now, calendar: calendar) else { return [] }
        return budgetAlerts.map { alert in
            InboxItem(
                id: "budget-\(alert.categoryID)", icon: .chartBars, category: alert.category,
                tone: alert.level == .exceeded ? .negative : .pending,
                title: alert.title, body: alert.body, bodyHasAmounts: true, destination: .summary,
            )
        }
    }

    private func priceIncreaseItems() -> [InboxItem] {
        priceIncreaseAlerts.map { alert in
            InboxItem(
                id: "price-\(alert.id)", icon: .subscription, category: nil, tone: .pending,
                title: alert.title, body: alert.body, bodyHasAmounts: true, destination: .recurring,
            )
        }
    }
}
