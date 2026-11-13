import Domain
import Foundation
import SwiftData

/// CloudKit-compatible: every attribute optional or defaulted, no unique constraints.
@Model
public final class AccountRecord: AuditedRecord {
    public var id = UUID()
    var name = ""
    var bank: String?
    var kindRaw = AccountKind.deposit.rawValue
    /// "USD:9306.78;NIO:0" — one entry per currency, principal first.
    var openingBalances = ""
    var openingDate = Date.distantPast
    var debtModeRaw: String?
    var limitAmount: String?
    var limitCurrency: String?
    var cutoffDay: Int?
    var dueDay: Int?
    var createdAt = Date.now
    /// Added in V5, with `deletedAt`: a deleted account stays as a tombstone so the deletion syncs.
    var updatedAt = Date.now
    var deletedAt: Date?
    /// When it was closed (`Account.closedAt`), from schema V14.
    var closedAt: Date?

    init(id: UUID) {
        self.id = id
    }

    func update(from account: Account) {
        name = account.name
        bank = account.bank
        kindRaw = account.kind.rawValue
        openingBalances = MoneyListCoding.string(account.openingBalances)
        openingDate = account.openingDate
        debtModeRaw = account.creditTerms?.debtMode.rawValue
        limitAmount = account.creditTerms?.limit.map { DecimalCoding.string($0.amount) }
        limitCurrency = account.creditTerms?.limit?.currency
        cutoffDay = account.creditTerms?.cutoffDay
        dueDay = account.creditTerms?.dueDay
        closedAt = account.closedAt
    }

    func toDomain() throws(DomainCorruption) -> Account {
        guard let kind = AccountKind(rawValue: kindRaw) else { throw DomainCorruption("Account kind \(kindRaw)") }
        var terms: CreditTerms?
        if let debtModeRaw {
            guard let mode = DebtMode(rawValue: debtModeRaw) else { throw DomainCorruption("Debt mode \(debtModeRaw)") }
            var limit: Money?
            if let limitAmount, let limitCurrency {
                limit = try Money(DecimalCoding.decimal(limitAmount), limitCurrency)
            }
            do {
                terms = try CreditTerms(debtMode: mode, limit: limit, cutoffDay: cutoffDay, dueDay: dueDay)
            } catch {
                throw DomainCorruption("Credit terms: \(error)")
            }
        }
        return try Account(
            id: id,
            name: name,
            bank: bank,
            kind: kind,
            openingBalances: MoneyListCoding.list(openingBalances),
            openingDate: openingDate,
            creditTerms: terms,
            closedAt: closedAt,
        )
    }
}

enum MoneyListCoding {
    static func string(_ list: [Money]) -> String {
        list.map { "\($0.currency):\(DecimalCoding.string($0.amount))" }.joined(separator: ";")
    }

    static func list(_ string: String) throws(DomainCorruption) -> [Money] {
        var result: [Money] = []
        for entry in string.split(separator: ";") {
            let parts = entry.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { throw DomainCorruption("Money entry \(entry)") }
            try result.append(Money(DecimalCoding.decimal(String(parts[1])), String(parts[0])))
        }
        return result
    }
}
