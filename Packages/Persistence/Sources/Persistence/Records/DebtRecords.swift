import Domain
import Foundation
import SwiftData

/// A loan. Every property is optional or defaulted and nothing is unique, as CloudKit requires.
/// Its few paid installments are stored as JSON text on the row rather than as related records:
/// they only ever change with the loan, and a relationship would need its own CloudKit record type.
@Model
public final class LoanRecord: AuditedRecord {
    public var id = UUID()
    var name = ""
    var lender: String?
    var borrowedAmount = "0"
    var borrowedCurrency = ""
    var installmentAmount = "0"
    var installmentCount = 1
    var frequencyRaw = LoanFrequency.monthly.rawValue
    var firstDueDate = Date.distantPast
    /// `[StoredPayment]` as JSON.
    var paymentsJSON = "[]"
    var createdAt = Date.now
    var updatedAt = Date.now
    var deletedAt: Date?

    init(id: UUID) {
        self.id = id
    }

    private struct StoredPayment: Codable {
        let number: Int
        let paidAt: Date
        let transactionID: UUID?
    }

    func update(from loan: Loan) {
        name = loan.name
        lender = loan.lender
        borrowedAmount = DecimalCoding.string(loan.borrowed.amount)
        borrowedCurrency = loan.borrowed.currency
        installmentAmount = DecimalCoding.string(loan.installmentAmount)
        installmentCount = loan.installmentCount
        frequencyRaw = loan.frequency.rawValue
        firstDueDate = loan.firstDueDate
        let stored = loan.payments.map { StoredPayment(number: $0.number, paidAt: $0.paidAt, transactionID: $0.transactionID) }
        paymentsJSON = JSONText.encode(stored)
    }

    func toDomain() throws(DomainCorruption) -> Loan {
        guard let frequency = LoanFrequency(rawValue: frequencyRaw) else {
            throw DomainCorruption("Loan frequency '\(frequencyRaw)'")
        }
        let stored: [StoredPayment] = try JSONText.decode(paymentsJSON, what: "Loan payments")
        return try Loan(
            id: id,
            name: name,
            lender: lender,
            borrowed: Money(DecimalCoding.decimal(borrowedAmount), borrowedCurrency),
            installmentAmount: DecimalCoding.decimal(installmentAmount),
            installmentCount: installmentCount,
            frequency: frequency,
            firstDueDate: firstDueDate,
            payments: stored.map { LoanPayment(number: $0.number, paidAt: $0.paidAt, transactionID: $0.transactionID) },
        )
    }
}

/// A personal debt, with its repayments as JSON text like a loan's payments. Amounts inside are
/// exact decimal strings like every other amount in the store.
@Model
public final class PersonalDebtRecord: AuditedRecord {
    public var id = UUID()
    var person = ""
    var directionRaw = DebtDirection.theyOweMe.rawValue
    var amount = "0"
    var currency = ""
    var date = Date.distantPast
    var note: String?
    /// `[StoredRepayment]` as JSON.
    var repaymentsJSON = "[]"
    var settledAt: Date?
    var transactionID: UUID?
    var createdAt = Date.now
    var updatedAt = Date.now
    var deletedAt: Date?

    init(id: UUID) {
        self.id = id
    }

    private struct StoredRepayment: Codable {
        let amount: String
        let date: Date
    }

    func update(from debt: PersonalDebt) {
        person = debt.person
        directionRaw = debt.direction.rawValue
        amount = DecimalCoding.string(debt.amount.amount)
        currency = debt.amount.currency
        date = debt.date
        note = debt.note
        repaymentsJSON = JSONText.encode(debt.repayments.map { StoredRepayment(amount: DecimalCoding.string($0.amount), date: $0.date) })
        settledAt = debt.settledAt
        transactionID = debt.transactionID
    }

    func toDomain() throws(DomainCorruption) -> PersonalDebt {
        guard let direction = DebtDirection(rawValue: directionRaw) else {
            throw DomainCorruption("Debt direction '\(directionRaw)'")
        }
        let stored: [StoredRepayment] = try JSONText.decode(repaymentsJSON, what: "Debt repayments")
        var repayments: [DebtRepayment] = []
        for row in stored {
            try repayments.append(DebtRepayment(amount: DecimalCoding.decimal(row.amount), date: row.date))
        }
        return try PersonalDebt(
            id: id,
            person: person,
            direction: direction,
            amount: Money(DecimalCoding.decimal(amount), currency),
            date: date,
            note: note,
            repayments: repayments,
            settledAt: settledAt,
            transactionID: transactionID,
        )
    }
}

/// Small lists kept on a row as JSON. Dates go as seconds, which round-trip a `Date` exactly.
enum JSONText {
    static func encode(_ value: some Encodable) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    static func decode<T: Decodable>(_ text: String, what: String) throws(DomainCorruption) -> T {
        do {
            return try JSONDecoder().decode(T.self, from: Data(text.utf8))
        } catch {
            throw DomainCorruption("\(what) '\(text)'")
        }
    }
}
