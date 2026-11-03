import Domain
import Foundation

/// How a month ended, so the screen can say "you saved" or "you overspent" instead of leaving the
/// person to subtract two numbers.
public enum CashFlowOutcome: Hashable, Sendable {
    /// More came in than went out; the amount is the surplus.
    case saved(Decimal)
    /// More went out than came in; the amount is the shortfall, always positive.
    case overspent(Decimal)
    /// Money moved and both sides matched exactly.
    case even
    /// Nothing confirmed came in or went out.
    case noActivity

    public init(income: Decimal, expense: Decimal) {
        let net = income - expense
        self = if income == 0, expense == 0 {
            .noActivity
        } else if net > 0 {
            .saved(net)
        } else if net < 0 {
            .overspent(-net)
        } else {
            .even
        }
    }
}

extension MonthlySummary {
    public var outcome: CashFlowOutcome {
        CashFlowOutcome(income: income, expense: expense)
    }
}

/// The whole window at a glance: what was left over across all of it and how often a month ran
/// short. Every month is already in the principal currency, so adding them up is safe.
public struct CashFlowTrend: Hashable, Sendable {
    public let income: Decimal
    public let expense: Decimal
    public let monthsSaved: Int
    public let monthsOverspent: Int

    public init(months: [MonthlySummary]) {
        income = months.reduce(0) { $0 + $1.income }
        expense = months.reduce(0) { $0 + $1.expense }
        monthsSaved = months.count {
            if case .saved = $0.outcome {
                true
            } else {
                false
            }
        }
        monthsOverspent = months.count {
            if case .overspent = $0.outcome {
                true
            } else {
                false
            }
        }
    }

    public var net: Decimal {
        income - expense
    }

    /// `nil` without income, for the same reason as `MonthlySummary.savingsRate`.
    public var savingsRate: Decimal? {
        income > 0 ? net / income : nil
    }

    public var outcome: CashFlowOutcome {
        CashFlowOutcome(income: income, expense: expense)
    }
}
