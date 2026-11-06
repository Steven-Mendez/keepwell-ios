import Foundation

/// One row of a loan's schedule.
public struct LoanInstallment: Hashable, Sendable {
    public let number: Int
    public let dueDate: Date
    /// `nil` while unpaid.
    public let payment: LoanPayment?

    public var isPaid: Bool {
        payment != nil
    }
}

/// A loan's schedule and where it stands. The debts screen, home and its reminders all read it from
/// here, and the web app follows the same rules.
public struct LoanProgress: Hashable, Sendable {
    public let loan: Loan
    public let installments: [LoanInstallment]
    /// Installments still unpaid times the installment amount.
    public let remaining: Decimal
    /// Every installment together, interest included.
    public let totalToPay: Decimal
    /// The lowest unpaid installment, `nil` once paid off.
    public let next: LoanInstallment?
    /// The next installment's day is before today.
    public let isNextOverdue: Bool

    public init(loan: Loan, today: Date, calendar: Calendar) {
        self.loan = loan
        let paid = Dictionary(loan.payments.map { ($0.number, $0) }) { first, _ in first }
        installments = (1 ... max(loan.installmentCount, 1)).map { number in
            LoanInstallment(
                number: number,
                dueDate: Self.dueDate(of: number, loan: loan, calendar: calendar),
                payment: paid[number],
            )
        }
        let unpaid = max(loan.installmentCount - loan.paidCount, 0)
        remaining = loan.installmentAmount * Decimal(unpaid)
        totalToPay = loan.installmentAmount * Decimal(loan.installmentCount)
        next = installments.first { !$0.isPaid }
        isNextOverdue = next.map { calendar.startOfDay(for: $0.dueDate) < calendar.startOfDay(for: today) } ?? false
    }

    public var isPaidOff: Bool {
        next == nil
    }

    public var remainingMoney: Money {
        Money(remaining, loan.borrowed.currency)
    }

    /// Always counted from the first due date, never from the previous (possibly clamped) one, so
    /// a loan due on the 31st stays on the 31st in the months that have one, like recurring rules.
    public static func dueDate(of number: Int, loan: Loan, calendar: Calendar) -> Date {
        let steps = number - 1
        let date = switch loan.frequency {
        case .weekly: calendar.date(byAdding: .day, value: 7 * steps, to: loan.firstDueDate)
        case .monthly: calendar.date(byAdding: .month, value: steps, to: loan.firstDueDate)
        }
        return date ?? loan.firstDueDate
    }

    /// Open loans first, the soonest next installment first; paid-off ones last. Ties go by name.
    public static func ordered(_ loans: [Loan], today: Date, calendar: Calendar) -> [Self] {
        loans.map { Self(loan: $0, today: today, calendar: calendar) }.sorted { lhs, rhs in
            switch (lhs.next, rhs.next) {
            case let (left?, right?) where left.dueDate != right.dueDate: left.dueDate < right.dueDate
            case (.some, nil): true
            case (nil, .some): false
            default: DebtOrder.byName(lhs.loan.name, lhs.loan.id, rhs.loan.name, rhs.loan.id)
            }
        }
    }
}

/// "You owe" and "Owed to you", one amount per currency: loans and personal debts in different
/// currencies are never added together.
public struct DebtTotals: Hashable, Sendable {
    /// What is left on open loans and on open debts the person owes, by currency code.
    public let youOwe: [Money]
    /// What is left on open debts people owe the person, by currency code.
    public let owedToYou: [Money]

    public init(loans: [Loan], debts: [PersonalDebt]) {
        var owe: [String: Decimal] = [:]
        var owed: [String: Decimal] = [:]
        for loan in loans where !loan.isPaidOff {
            owe[loan.borrowed.currency, default: 0] += loan.installmentAmount * Decimal(loan.installmentCount - loan.paidCount)
        }
        for debt in debts where !debt.isSettled && debt.remaining > 0 {
            switch debt.direction {
            case .iOwe: owe[debt.amount.currency, default: 0] += debt.remaining
            case .theyOweMe: owed[debt.amount.currency, default: 0] += debt.remaining
            }
        }
        youOwe = Self.lines(owe)
        owedToYou = Self.lines(owed)
    }

    private static func lines(_ totals: [String: Decimal]) -> [Money] {
        totals.filter { $0.value > 0 }.sorted { $0.key < $1.key }.map { Money($0.value, $0.key) }
    }
}

public enum PersonalDebtOrder {
    /// Open debts first, newest first; settled ones after them, also newest first.
    public static func ordered(_ debts: [PersonalDebt]) -> [PersonalDebt] {
        debts.sorted { lhs, rhs in
            if lhs.isSettled != rhs.isSettled {
                return !lhs.isSettled
            }
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }
            return DebtOrder.byName(lhs.person, lhs.id, rhs.person, rhs.id)
        }
    }
}

enum DebtOrder {
    static func byName(_ lhsName: String, _ lhsID: UUID, _ rhsName: String, _ rhsID: UUID) -> Bool {
        let byName = lhsName.localizedCaseInsensitiveCompare(rhsName)
        if byName != .orderedSame {
            return byName == .orderedAscending
        }
        // Same name: the id keeps the order stable between loads.
        return lhsID.uuidString < rhsID.uuidString
    }
}

/// Splitting an expense between the person and others, each of whom then owes their share.
public enum BillSplit {
    /// Each share when `total` is split equally between the person and `people` others, rounded
    /// down to the cent so the shares never add up past what was paid.
    public static func equalShare(of total: Decimal, people: Int) -> Decimal {
        guard people > 0, total > 0 else { return 0 }
        return (total / Decimal(people + 1)).rounded(scale: 2, mode: .down)
    }

    /// Every share positive and all of them together no more than the bill: the person paid it, so
    /// others can owe at most all of it.
    public static func check(_ shares: [Decimal], total: Decimal) throws(DomainError) {
        guard !shares.isEmpty, shares.allSatisfy({ $0 > 0 }), shares.reduce(0, +) <= total else { throw .invalidAmount }
    }
}
