import Domain
import Foundation

/// What the Plan hub previews: one summary per planning screen it leads to.
public struct PlanOverview: Hashable, Sendable {
    public struct Recurring: Hashable, Sendable {
        /// Live expense subscriptions per month, in the principal currency.
        public let subscriptionsPerMonth: Money
        /// The first recurring movement still to come, `nil` when nothing is scheduled.
        public let next: RecurringOccurrence?
        public let hasRules: Bool

        public init(subscriptionsPerMonth: Money, next: RecurringOccurrence?, hasRules: Bool) {
            self.subscriptionsPerMonth = subscriptionsPerMonth
            self.next = next
            self.hasRules = hasRules
        }
    }

    public struct Goals: Hashable, Sendable {
        /// The first goal in list order, the one most in need of attention.
        public let top: SavingsGoalProgress?
        public let count: Int

        public init(top: SavingsGoalProgress?, count: Int) {
            self.top = top
            self.count = count
        }
    }

    public struct Debts: Hashable, Sendable {
        public let totals: DebtTotals
        /// The open loan whose installment comes first.
        public let nextLoan: LoanProgress?
        public let hasDebts: Bool

        public init(totals: DebtTotals, nextLoan: LoanProgress?, hasDebts: Bool) {
            self.totals = totals
            self.nextLoan = nextLoan
            self.hasDebts = hasDebts
        }
    }

    public let recurring: Recurring
    public let goals: Goals
    public let debts: Debts

    public init(recurring: Recurring, goals: Goals, debts: Debts) {
        self.recurring = recurring
        self.goals = goals
        self.debts = debts
    }
}
