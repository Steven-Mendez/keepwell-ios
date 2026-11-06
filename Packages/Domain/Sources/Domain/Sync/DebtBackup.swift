import Foundation

/// A loan in the backup file (schema 4). The installment amount is in the borrowed currency, so it
/// is a bare decimal string like a goal's `saved`.
public struct LoanBackup: Codable, Sendable, Equatable {
    public struct Payment: Codable, Sendable, Equatable {
        public let number: Int
        public let paidAt: Date
        public let transactionId: String?
    }

    public let id: String
    public let name: String
    public let lender: String?
    public let borrowed: MoneyBackup
    public let installmentAmount: String
    public let installmentCount: Int
    public let frequency: LoanFrequency
    public let firstDueDate: Date
    public let payments: [Payment]
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?

    init(_ stamped: Stamped<Loan>) {
        let loan = stamped.value
        id = PortableID.string(loan.id)
        name = loan.name
        lender = loan.lender
        borrowed = MoneyBackup(loan.borrowed)
        installmentAmount = PortableDecimal.string(loan.installmentAmount)
        installmentCount = loan.installmentCount
        frequency = loan.frequency
        firstDueDate = loan.firstDueDate
        payments = loan.payments.map {
            Payment(number: $0.number, paidAt: $0.paidAt, transactionId: $0.transactionID.map(PortableID.string))
        }
        createdAt = stamped.metadata.createdAt
        updatedAt = stamped.metadata.updatedAt
        deletedAt = stamped.metadata.deletedAt
    }

    /// Checked as saving checks it; the currency isn't held to the settings, since a loan keeps the
    /// currency it was created in. A payment's movement may be a tombstone in the same file.
    func toDomain() throws(DomainError) -> Stamped<Loan> {
        var rows: [LoanPayment] = []
        for payment in payments {
            try rows.append(LoanPayment(
                number: payment.number,
                paidAt: payment.paidAt,
                transactionID: payment.transactionId.map { id throws(DomainError) in try PortableID.uuid(id) },
            ))
        }
        let loan = try Loan(
            id: PortableID.uuid(id),
            name: name,
            lender: lender,
            borrowed: borrowed.toDomain(),
            installmentAmount: PortableDecimal.decimal(installmentAmount),
            installmentCount: installmentCount,
            frequency: frequency,
            firstDueDate: firstDueDate,
            payments: rows,
        )
        try loan.check()
        return Stamped(loan, RecordMetadata(createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt))
    }
}

/// A personal debt in the backup file (schema 4). Repayments are in the debt's currency.
public struct PersonalDebtBackup: Codable, Sendable, Equatable {
    public struct Repayment: Codable, Sendable, Equatable {
        public let amount: String
        public let date: Date
    }

    public let id: String
    public let person: String
    public let direction: DebtDirection
    public let amount: MoneyBackup
    public let date: Date
    public let note: String?
    public let repayments: [Repayment]
    public let settledAt: Date?
    /// The expense it was split from.
    public let transactionId: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?

    init(_ stamped: Stamped<PersonalDebt>) {
        let debt = stamped.value
        id = PortableID.string(debt.id)
        person = debt.person
        direction = debt.direction
        amount = MoneyBackup(debt.amount)
        date = debt.date
        note = debt.note
        repayments = debt.repayments.map { Repayment(amount: PortableDecimal.string($0.amount), date: $0.date) }
        settledAt = debt.settledAt
        transactionId = debt.transactionID.map(PortableID.string)
        createdAt = stamped.metadata.createdAt
        updatedAt = stamped.metadata.updatedAt
        deletedAt = stamped.metadata.deletedAt
    }

    func toDomain() throws(DomainError) -> Stamped<PersonalDebt> {
        var rows: [DebtRepayment] = []
        for repayment in repayments {
            try rows.append(DebtRepayment(amount: PortableDecimal.decimal(repayment.amount), date: repayment.date))
        }
        let debt = try PersonalDebt(
            id: PortableID.uuid(id),
            person: person,
            direction: direction,
            amount: amount.toDomain(),
            date: date,
            note: note,
            repayments: rows,
            settledAt: settledAt,
            transactionID: transactionId.map { id throws(DomainError) in try PortableID.uuid(id) },
        )
        try debt.checkAmounts()
        return Stamped(debt, RecordMetadata(createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt))
    }
}
