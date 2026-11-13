import Foundation

/// How often a loan's installments fall due.
public enum LoanFrequency: String, Codable, CaseIterable, Sendable {
    /// Every 7 days.
    case weekly
    case monthly
}

/// One installment the person paid: which one, when, and the movement that paid it. The movement
/// is `nil` only when it no longer exists or came from a file without one.
public struct LoanPayment: Hashable, Sendable, Codable {
    /// 1...installmentCount
    public let number: Int
    public let paidAt: Date
    public let transactionID: UUID?

    public init(number: Int, paidAt: Date, transactionID: UUID? = nil) {
        self.number = number
        self.paidAt = paidAt
        self.transactionID = transactionID
    }
}

/// A bank or personal loan the person pays off in equal installments ("Moto: C$1,800 a month,
/// 12 installments"). Paying an installment records a real expense; the loan itself only keeps the
/// schedule and which installments are paid, so balances always come from movements.
public struct Loan: Identifiable, Hashable, Sendable, Codable {
    /// Same as a goal's: one line in a row.
    public static let maxNameLength = 60
    /// Fifty years of monthly installments, or about eleven of weekly ones.
    public static let installmentCountRange = 1 ... 600

    public let id: UUID
    public let name: String
    /// The bank or person who lent it, when the person says.
    public let lender: String?
    /// What was borrowed, in the principal or second currency. Always positive.
    public let borrowed: Money
    /// Each installment, in `borrowed`'s currency. Always positive; with interest the installments
    /// add up to more than what was borrowed.
    public let installmentAmount: Decimal
    public let installmentCount: Int
    public let frequency: LoanFrequency
    /// The first installment's due day; the others follow it by `frequency`.
    public let firstDueDate: Date
    /// By installment number.
    public let payments: [LoanPayment]

    public init(
        id: UUID = UUID(),
        name: String,
        lender: String? = nil,
        borrowed: Money,
        installmentAmount: Decimal,
        installmentCount: Int,
        frequency: LoanFrequency = .monthly,
        firstDueDate: Date,
        payments: [LoanPayment] = [],
    ) {
        self.id = id
        self.name = name
        self.lender = lender
        self.borrowed = borrowed
        self.installmentAmount = installmentAmount
        self.installmentCount = installmentCount
        self.frequency = frequency
        self.firstDueDate = firstDueDate
        self.payments = payments.sorted { $0.number < $1.number }
    }

    /// `installmentAmount` with its currency.
    public var installment: Money {
        Money(installmentAmount, borrowed.currency)
    }

    public var paidCount: Int {
        payments.count
    }

    public var isPaidOff: Bool {
        paidCount >= installmentCount
    }

    /// The lowest installment not paid yet, `nil` once the loan is paid off.
    public var nextNumber: Int? {
        let paid = Set(payments.map(\.number))
        return (1 ... installmentCount).first { !paid.contains($0) }
    }

    /// What every loan holds however it arrives, from the editor or a backup file: positive amounts,
    /// a count in range and each payment naming a distinct installment of the schedule.
    public func check() throws(DomainError) {
        guard borrowed.amount > 0, installmentAmount > 0, Self.installmentCountRange.contains(installmentCount) else {
            throw .invalidAmount
        }
        let numbers = payments.map(\.number)
        guard Set(numbers).count == numbers.count, numbers.allSatisfy({ (1 ... installmentCount).contains($0) }) else {
            throw .corruptedData("Loan payments \(numbers) of \(installmentCount)")
        }
    }

    /// "Pay installment": marks the next one paid by `transactionID`. Throws once paid off.
    public func paying(at date: Date, transactionID: UUID?) throws(DomainError) -> Self {
        guard let number = nextNumber else { throw .invalidAmount }
        return with(payments: payments + [LoanPayment(number: number, paidAt: date, transactionID: transactionID)])
    }

    /// "Mark unpaid": the installment back to due. Throws when it isn't paid.
    public func unpaying(number: Int) throws(DomainError) -> (loan: Self, payment: LoanPayment) {
        guard let payment = payments.first(where: { $0.number == number }) else { throw .invalidAmount }
        return (with(payments: payments.filter { $0.number != number }), payment)
    }

    public func with(payments: [LoanPayment]) -> Self {
        Self(
            id: id, name: name, lender: lender, borrowed: borrowed, installmentAmount: installmentAmount,
            installmentCount: installmentCount, frequency: frequency, firstDueDate: firstDueDate, payments: payments,
        )
    }
}

/// Who owes whom in a personal debt.
public enum DebtDirection: String, Codable, CaseIterable, Sendable {
    /// "I lent Juan C$500": Juan owes the person.
    case theyOweMe
    /// "Juan lent me C$500": the person owes Juan.
    case iOwe
}

/// Part of a personal debt paid back, in the debt's currency.
public struct DebtRepayment: Hashable, Sendable, Codable {
    /// Its own id, so a repayment syncs as a row of its own (ADR 0005 in keepwell-api) and two
    /// devices can each record one. Older stores and backups get `NameBasedID.legacyRepayment`.
    public let id: UUID
    /// Always positive.
    public let amount: Decimal
    public let date: Date
    /// The income movement that deposited it into an account ("Deposit into account"), created
    /// with it and deleted with it; `nil` when it was only recorded. That movement changes the
    /// balance but isn't income: the money only came back (`Transaction.isReimbursement`).
    public let transactionID: UUID?

    public init(id: UUID = UUID(), amount: Decimal, date: Date, transactionID: UUID? = nil) {
        self.id = id
        self.amount = amount
        self.date = date
        self.transactionID = transactionID
    }
}

/// Money lent to or borrowed from a person, outside any bank ("I lent Juan C$500"). Like savings
/// goals it is tracked on its own: recording, repaying or settling it never records a movement or
/// changes a balance, because the cash may have changed hands in ways the ledger never saw; except
/// a repayment the person deposits into an account (`DebtRepayment.transactionID`). A "they owe
/// me" debt split from an expense (`transactionID`) takes its share out of the person's spending
/// (`Transaction.spendingAmount(in:debts:)`).
public struct PersonalDebt: Identifiable, Hashable, Sendable, Codable {
    public static let maxNameLength = 60

    public let id: UUID
    /// Who lent or borrowed.
    public let person: String
    public let direction: DebtDirection
    /// Always positive, in the principal or second currency when created.
    public let amount: Money
    public let date: Date
    public let note: String?
    /// Oldest first.
    public let repayments: [DebtRepayment]
    /// When it was settled: by the last repayment, or by hand with something still left (forgiven
    /// or paid in kind). `nil` while open.
    public let settledAt: Date?
    /// The expense it was split from, when it came from "Split".
    public let transactionID: UUID?
    /// When it should be paid back, the start of that day; `nil` for a debt without one. Never
    /// before `date` (`SavePersonalDebtUseCase`).
    public let dueDate: Date?

    public init(
        id: UUID = UUID(),
        person: String,
        direction: DebtDirection,
        amount: Money,
        date: Date,
        note: String? = nil,
        repayments: [DebtRepayment] = [],
        settledAt: Date? = nil,
        transactionID: UUID? = nil,
        dueDate: Date? = nil,
    ) {
        self.id = id
        self.person = person
        self.direction = direction
        self.amount = amount
        self.date = date
        self.note = note
        self.repayments = repayments
        self.settledAt = settledAt
        self.transactionID = transactionID
        self.dueDate = dueDate
    }

    public var repaid: Decimal {
        repayments.reduce(0) { $0 + $1.amount }
    }

    /// What is still owed, never below zero.
    public var remaining: Decimal {
        max(amount.amount - repaid, 0)
    }

    public var remainingMoney: Money {
        Money(remaining, amount.currency)
    }

    public var isSettled: Bool {
        settledAt != nil
    }

    /// A positive amount, positive repayments that never add up past it.
    public func checkAmounts() throws(DomainError) {
        guard amount.amount > 0, repayments.allSatisfy({ $0.amount > 0 }), repaid <= amount.amount else {
            throw .invalidAmount
        }
    }

    /// "Record repayment": a positive amount no larger than what is left. Paying the rest settles
    /// it. `transactionID` is the income movement that deposited it, when it was deposited.
    public func repaying(_ value: Decimal, on day: Date, transactionID: UUID? = nil, id: UUID = UUID()) throws(DomainError) -> Self {
        guard !isSettled, value > 0, value <= remaining else { throw .invalidAmount }
        let repayments = repayments + [DebtRepayment(id: id, amount: value, date: day, transactionID: transactionID)]
        let isPaid = repaid + value >= amount.amount
        return with(repayments: repayments, settledAt: isPaid ? day : nil)
    }

    /// Takes one repayment out. A debt that repayment settled (settled the moment it was paid)
    /// opens again; one settled by hand stays settled. Throws `.notFound` for an unknown repayment.
    public func removingRepayment(id: UUID) throws(DomainError) -> (debt: Self, repayment: DebtRepayment) {
        guard let repayment = repayments.first(where: { $0.id == id }) else { throw .notFound(id) }
        let reopens = settledAt != nil && settledAt == repayment.date
        return (with(repayments: repayments.filter { $0.id != id }, settledAt: reopens ? nil : settledAt), repayment)
    }

    /// Where a deposited repayment is filed as income: "Refunds", or "Other income" once it was
    /// deleted.
    public static func repaymentCategoryID(in categories: [TransactionCategory]) -> String {
        categories.contains { $0.id == repaymentCategoryID && $0.kind == .income }
            ? repaymentCategoryID
            : TransactionCategory.otherIncomeID
    }

    public static let repaymentCategoryID = "refunds"

    /// "Ana · Dinner": a deposited repayment's description, the same on every app (the person,
    /// then the debt's note).
    public var repaymentDescription: String {
        let note = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return note.isEmpty ? person : "\(person) · \(note)"
    }

    /// "Mark as settled", even with something left.
    public func settled(at day: Date) -> Self {
        with(repayments: repayments, settledAt: day)
    }

    /// Opens a settled debt again; only one with something left can be owed again.
    public func reopened() throws(DomainError) -> Self {
        guard remaining > 0 else { throw .invalidAmount }
        return with(repayments: repayments, settledAt: nil)
    }

    public func with(repayments: [DebtRepayment], settledAt: Date?) -> Self {
        Self(
            id: id, person: person, direction: direction, amount: amount, date: date, note: note,
            repayments: repayments, settledAt: settledAt, transactionID: transactionID, dueDate: dueDate,
        )
    }
}

extension Loan {
    /// A paid installment's id when it syncs as its own row: the same installment paid on two
    /// devices is one record (`loanPayment` in keepwell-web's schema/id.ts).
    public func paymentID(for payment: LoanPayment) -> UUID {
        NameBasedID.loanPayment(loanID: id, number: payment.number)
    }
}
