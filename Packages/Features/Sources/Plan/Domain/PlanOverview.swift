import Domain
import Foundation

/// What the Plan hub previews: one summary per planning screen it leads to.
public struct PlanOverview: Hashable, Sendable {
    public struct Recurring: Hashable, Sendable {
        /// Live expense subscriptions per month, in the principal currency.
        public let subscriptionsPerMonth: Money
        /// The rules `subscriptionsPerMonth` adds up: live expense subscriptions.
        public let subscriptionCount: Int
        /// The first recurring movement still to come, `nil` when nothing is scheduled.
        public let next: RecurringOccurrence?
        public let hasRules: Bool

        public init(subscriptionsPerMonth: Money, subscriptionCount: Int = 0, next: RecurringOccurrence?, hasRules: Bool) {
            self.subscriptionsPerMonth = subscriptionsPerMonth
            self.subscriptionCount = subscriptionCount
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
        /// Open loans and open debts the person owes: what `totals.youOwe` adds up.
        public let youOweCount: Int
        /// Different people with an open debt to the person: who `totals.owedToYou` adds up.
        public let peopleOwingCount: Int
        /// The open loan whose installment comes first.
        public let nextLoan: LoanProgress?
        public let hasDebts: Bool

        public init(
            totals: DebtTotals,
            youOweCount: Int = 0,
            peopleOwingCount: Int = 0,
            nextLoan: LoanProgress?,
            hasDebts: Bool,
        ) {
            self.totals = totals
            self.youOweCount = youOweCount
            self.peopleOwingCount = peopleOwingCount
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
