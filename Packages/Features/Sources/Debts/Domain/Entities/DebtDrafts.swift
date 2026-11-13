import Domain
import Foundation

/// A loan as the editor builds it. `id` is `nil` for a new loan. Payments are never part of it:
/// "Pay installment" records them, so editing can't overwrite them.
public struct LoanDraft: Hashable, Sendable {
    public var id: UUID?
    public var name: String
    public var lender: String
    /// When editing, only the amount is used: a loan keeps the currency it was created in.
    public var borrowed: Money
    public var installmentAmount: Decimal
    public var installmentCount: Int
    public var frequency: LoanFrequency
    public var firstDueDate: Date

    public init(
        id: UUID? = nil,
        name: String,
        lender: String = "",
        borrowed: Money,
        installmentAmount: Decimal,
        installmentCount: Int,
        frequency: LoanFrequency = .monthly,
        firstDueDate: Date,
    ) {
        self.id = id
        self.name = name
        self.lender = lender
        self.borrowed = borrowed
        self.installmentAmount = installmentAmount
        self.installmentCount = installmentCount
        self.frequency = frequency
        self.firstDueDate = firstDueDate
    }
}

/// A personal debt as the editor builds it. Repayments and settling are separate actions.
public struct PersonalDebtDraft: Hashable, Sendable {
    public var id: UUID?
    public var person: String
    public var direction: DebtDirection
    /// When editing, only the amount is used, and it can't drop below what was already repaid.
    public var amount: Money
    public var date: Date
    public var note: String
    /// When it should be paid back, saved as the start of that day. `nil` saves it without one, also
    /// when editing: that is how a due date is removed.
    public var dueDate: Date?

    public init(
        id: UUID? = nil,
        person: String,
        direction: DebtDirection,
        amount: Money,
        date: Date,
        note: String = "",
        dueDate: Date? = nil,
    ) {
        self.id = id
        self.person = person
        self.direction = direction
        self.amount = amount
        self.date = date
        self.note = note
        self.dueDate = dueDate
    }
}

/// Where an installment is paid from: a card or transfer channel, or an account without one (cash).
/// The same choice a movement's payment method is.
public enum InstallmentSource: Hashable, Sendable {
    case card(UUID)
    case account(UUID)
}

/// "Pay installment": where the money comes from, its category and the day it was paid.
public struct InstallmentPayment: Hashable, Sendable {
    public var loanID: UUID
    public var source: InstallmentSource
    public var categoryID: String
    public var date: Date

    public init(loanID: UUID, source: InstallmentSource, categoryID: String, date: Date) {
        self.loanID = loanID
        self.source = source
        self.categoryID = categoryID
        self.date = date
    }
}

/// The expense an installment records, as any movement the person types.
public struct InstallmentExpense: Hashable, Sendable {
    public let amount: Money
    public let categoryID: String
    public let source: InstallmentSource
    /// "Motorbike · 3/12".
    public let description: String
    public let date: Date

    public init(amount: Money, categoryID: String, source: InstallmentSource, description: String, date: Date) {
        self.amount = amount
        self.categoryID = categoryID
        self.source = source
        self.description = description
        self.date = date
    }
}

/// Builds an installment's expense, checked but not stored: the loan repository stores it with the
/// loan in one write. The app implements it with the same rules as a movement the person types.
public protocol InstallmentExpenseRecorder: Sendable {
    func prepare(_ expense: InstallmentExpense) async throws(DomainError) -> Transaction
}

/// One person's share of a split expense.
public struct SplitShare: Hashable, Sendable {
    public var person: String
    public var amount: Decimal

    public init(person: String, amount: Decimal) {
        self.person = person
        self.amount = amount
    }
}

/// Everything the debts screen shows.
public struct DebtsOverview: Hashable, Sendable {
    public let currencies: CurrencySettings
    /// Open loans first, soonest installment first.
    public let loans: [LoanProgress]
    /// Open debts with a due date first, soonest first; then open ones, newest first.
    public let debts: [PersonalDebt]
    public let totals: DebtTotals

    public init(currencies: CurrencySettings, loans: [Loan], debts: [PersonalDebt], today: Date, calendar: Calendar) {
        self.currencies = currencies
        self.loans = LoanProgress.ordered(loans, today: today, calendar: calendar)
        self.debts = PersonalDebtOrder.ordered(debts)
        totals = DebtTotals(loans: loans, debts: debts)
    }

    public func loan(_ id: UUID) -> LoanProgress? {
        loans.first { $0.loan.id == id }
    }

    public func debt(_ id: UUID) -> PersonalDebt? {
        debts.first { $0.id == id }
    }
}
