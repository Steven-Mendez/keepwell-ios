import Domain
import Foundation

/// The line under home's greeting, counted from the same list as home's "Upcoming" card
/// (`UpcomingPayments`), so the line and the card never contradict each other. Port of
/// `homeStatus` in keepwell-web (`components/home/home-status.ts`).
public struct HomeStatus: Hashable, Sendable {
    /// Drafts dated today or before: the overdue and today's ones in home's "Upcoming" card.
    public var toConfirm = 0
    /// Loan installments past their day.
    public var overdue = 0
    /// Personal debts past their due date, either direction: the late ones "Upcoming" lists.
    public var overdueDebts = 0
    /// Card payments, installments and personal debts due today.
    public var dueToday = 0
    /// Card payments, installments and personal debts due tomorrow, subscriptions renewing tomorrow
    /// and bills due tomorrow (recurring expenses recorded as drafts), as the reminders count them.
    public var dueTomorrow = 0

    public var isClear: Bool {
        toConfirm == 0 && overdue == 0 && overdueDebts == 0 && dueToday == 0 && dueTomorrow == 0
    }

    public init(toConfirm: Int = 0, overdue: Int = 0, overdueDebts: Int = 0, dueToday: Int = 0, dueTomorrow: Int = 0) {
        self.toConfirm = toConfirm
        self.overdue = overdue
        self.overdueDebts = overdueDebts
        self.dueToday = dueToday
        self.dueTomorrow = dueTomorrow
    }

    public init(payments: [UpcomingPayment]) {
        for payment in payments {
            switch payment.kind {
            case .draft:
                if payment.status != .upcoming {
                    toConfirm += 1
                }
            case .installment where payment.status == .overdue:
                overdue += 1
            case .installment, .card:
                if payment.daysFromToday == 0 {
                    dueToday += 1
                } else if payment.daysFromToday == 1 {
                    dueTomorrow += 1
                }
            case let .recurring(rule):
                // A renewal, or a bill the person has to pay and confirm: what the reminders count.
                if payment.daysFromToday == 1, rule.isSubscription || (rule.kind == .expense && !rule.autoConfirm) {
                    dueTomorrow += 1
                }
            case .debt where payment.status == .overdue:
                // Either direction: the debt reminder covers both, and "Upcoming" lists both.
                overdueDebts += 1
            case .debt:
                if payment.daysFromToday == 0 {
                    dueToday += 1
                } else if payment.daysFromToday == 1 {
                    dueTomorrow += 1
                }
            }
        }
    }

    /// What `overview`'s "Upcoming" list says needs attention.
    public init(_ overview: HomeOverview) {
        self.init(payments: overview.upcomingPayments)
    }
}
