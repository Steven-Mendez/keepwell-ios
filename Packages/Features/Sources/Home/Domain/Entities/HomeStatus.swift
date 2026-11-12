import Domain
import Foundation

/// The line under home's greeting, counted from the same notifications as the inbox and the same
/// loans as the debts card, so it never says "All caught up" while home lists something late.
/// Port of `homeStatus` in keepwell-web (`components/home/home-status.ts`).
public struct HomeStatus: Hashable, Sendable {
    /// Drafts dated today or before: the late ones in home's drafts list.
    public var toConfirm = 0
    /// Loan installments past their day, which the debts card marks as overdue.
    public var overdue = 0
    /// Card payments and installments due today.
    public var dueToday = 0
    /// Card payments and installments due tomorrow, subscriptions renewing tomorrow and bills due tomorrow.
    public var dueTomorrow = 0

    public var isClear: Bool {
        toConfirm == 0 && overdue == 0 && dueToday == 0 && dueTomorrow == 0
    }

    public init(toConfirm: Int = 0, overdue: Int = 0, dueToday: Int = 0, dueTomorrow: Int = 0) {
        self.toConfirm = toConfirm
        self.overdue = overdue
        self.dueToday = dueToday
        self.dueTomorrow = dueTomorrow
    }

    public init(notifications: [LedgerNotification], loans: [LoanProgress]) {
        for notification in notifications {
            switch notification.subject {
            case .planned:
                toConfirm += 1
            case let .payment(_, _, _, daysLeft), let .installment(_, _, daysLeft):
                if daysLeft == 0 {
                    dueToday += 1
                } else if daysLeft == 1 {
                    dueTomorrow += 1
                }
            case .renewal, .bill:
                dueTomorrow += 1
            case .cutoff, .debt, .expiry, .budget, .price, .proposal:
                break
            }
        }
        overdue = loans.count(where: \.isNextOverdue)
    }

    /// What applies on the day of `now` in `overview`.
    public init(on now: Date, in overview: HomeOverview, calendar: Calendar) {
        self.init(
            notifications: LedgerNotifications.applying(on: now, in: overview, calendar: calendar),
            loans: overview.loans,
        )
    }
}
