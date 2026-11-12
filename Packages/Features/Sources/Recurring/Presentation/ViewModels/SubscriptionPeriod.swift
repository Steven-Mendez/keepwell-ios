import Domain

/// The four periods the short subscription form offers, each one an ordinary schedule: every 1, 3
/// or 6 months, or every year. Any other schedule is chosen under "More options".
public enum SubscriptionPeriod: CaseIterable, Hashable, Sendable {
    case monthly
    case quarterly
    case halfYearly
    case yearly

    public var frequency: RecurringFrequency {
        self == .yearly ? .yearly : .monthly
    }

    public var interval: Int {
        switch self {
        case .monthly, .yearly: 1
        case .quarterly: 3
        case .halfYearly: 6
        }
    }

    /// `nil` for a schedule none of the four covers (weekly, every 2 months…).
    public init?(frequency: RecurringFrequency, interval: Int) {
        guard let period = Self.allCases.first(where: { $0.frequency == frequency && $0.interval == interval }) else {
            return nil
        }
        self = period
    }
}
