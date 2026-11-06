import Foundation

/// The month a savings goal is due, like a card's "valid thru": a calendar month with no day or
/// time zone, so "December 2026" is December wherever the person opens the app.
public struct TargetMonth: Hashable, Sendable, Codable, Comparable {
    public static let yearRange = 2000 ... 2199

    /// 1...12
    public let month: Int
    public let year: Int

    public init(month: Int, year: Int) throws(DomainError) {
        guard (1 ... 12).contains(month), Self.yearRange.contains(year) else { throw .invalidTargetMonth }
        self.month = month
        self.year = year
    }

    public init(_ month: YearMonth) throws(DomainError) {
        try self.init(month: month.month, year: month.year)
    }

    /// Months since year 0, so two months subtract into a count without a calendar.
    var index: Int {
        year * 12 + (month - 1)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

/// Money the person sets aside for something ("Trip: C$15,000 by December"), like a Monzo Pot or
/// a Revolut Vault but only on paper: adding to or withdrawing from a goal never records a
/// movement or changes an account's balance, so the ledger stays a record of what really moved.
public struct SavingsGoal: Identifiable, Hashable, Sendable, Codable {
    /// Long enough for "Emergency fund for the car", short enough for one line in a row.
    public static let maxNameLength = 40

    public let id: UUID
    public let name: String
    /// Always positive.
    public let target: Money
    /// What is set aside so far, in `target`'s currency. Never negative; it may pass the target.
    public let saved: Decimal
    /// `nil` for a goal without a deadline, which then has no monthly figure.
    public let targetMonth: TargetMonth?
    /// An SF Symbol from the same choices categories offer.
    public let icon: String?
    /// A key of the category palette.
    public let color: String?

    public init(
        id: UUID = UUID(),
        name: String,
        target: Money,
        saved: Decimal = 0,
        targetMonth: TargetMonth? = nil,
        icon: String? = nil,
        color: String? = nil,
    ) {
        self.id = id
        self.name = name
        self.target = target
        self.saved = saved
        self.targetMonth = targetMonth
        self.icon = icon
        self.color = color
    }

    /// `saved` with its currency, for display next to the target.
    public var savedMoney: Money {
        Money(saved, target.currency)
    }

    /// A positive target and nothing negative set aside: what every goal holds however it arrives,
    /// from the editor or from a backup file.
    public func checkAmounts() throws(DomainError) {
        guard target.amount > 0, saved >= 0 else { throw .invalidAmount }
    }

    /// "Add money": only a positive amount.
    public func adding(_ amount: Decimal) throws(DomainError) -> Self {
        guard amount > 0 else { throw .invalidAmount }
        return with(saved: saved + amount)
    }

    /// "Withdraw": a positive amount no larger than what is set aside, so `saved` never goes negative.
    public func withdrawing(_ amount: Decimal) throws(DomainError) -> Self {
        guard amount > 0, amount <= saved else { throw .invalidAmount }
        return with(saved: saved - amount)
    }

    public func with(saved: Decimal) -> Self {
        Self(id: id, name: name, target: target, saved: saved, targetMonth: targetMonth, icon: icon, color: color)
    }
}
