import Domain
import Foundation

/// Bounds on a movement's amount in the principal currency, both inclusive; either may be left out
/// (web `AmountRange`).
public struct AmountRange: Hashable, Sendable {
    public var min: Decimal?
    public var max: Decimal?

    public init(min: Decimal? = nil, max: Decimal? = nil) {
        self.min = min
        self.max = max
    }

    public enum Problem: Hashable, Sendable { case minAboveMax }

    /// Why the range can't be applied; `nil` when it can.
    public var problem: Problem? {
        if let min, let max, min > max {
            return .minAboveMax
        }
        return nil
    }

    public var isEmpty: Bool {
        min == nil && max == nil
    }

    /// Whether the movement's amount in the principal currency, converted with the rate it recorded
    /// (the figure the totals add up), falls in the range. Compared rounded to cents, as shown:
    /// 99.996 reads 100.00 and passes "at least 100". A minimum above the maximum matches nothing.
    public func contains(_ transaction: Transaction, principal: String) -> Bool {
        guard problem == nil else { return false }
        let amount = transaction.amount(in: principal).rounded(scale: 2, mode: .plain)
        if let min, amount < min {
            return false
        }
        if let max, amount > max {
            return false
        }
        return true
    }
}

/// Where a movement came from: anything, a subscription's rule, or one recurring rule (web
/// `TransactionOrigin`).
public enum TransactionOrigin: Hashable, Sendable {
    case any
    case subscriptions
    case rule(UUID)

    /// A rule matches by `recurringID`, even once deleted; a subscription needs the rule to still
    /// exist and be one today (paused counts). Movements logged by hand match neither.
    public func matches(_ transaction: Transaction, rules: [RecurringRule]) -> Bool {
        switch self {
        case .any:
            true
        case let .rule(id):
            transaction.recurringID == id
        case .subscriptions:
            transaction.recurringID.map { id in rules.contains { $0.id == id && $0.isSubscription } } ?? false
        }
    }
}

/// What the amount and origin filters read: the principal currency and the recurring rules.
public struct TransactionQueryContext: Sendable {
    public let principal: String
    public let rules: [RecurringRule]

    public init(principal: String, rules: [RecurringRule]) {
        self.principal = principal
        self.rules = rules
    }
}
