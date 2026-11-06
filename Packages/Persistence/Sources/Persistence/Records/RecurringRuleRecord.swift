import Domain
import Foundation
import SwiftData

/// A recurring rule. Every property is optional or defaulted and nothing is unique, as CloudKit
/// requires; amounts are exact decimal strings like the movements they produce.
@Model
public final class RecurringRuleRecord: AuditedRecord {
    public var id = UUID()
    var name = ""
    var kindRaw = TransactionKind.expense.rawValue
    var categoryID: String?
    var amount = "0"
    var currency = ""
    var accountID = UUID()
    var cardID: UUID?
    var destinationAccountID: UUID?
    var frequencyRaw = RecurringFrequency.monthly.rawValue
    var interval = 1
    var startDate = Date.distantPast
    /// Indexed: every launch looks for the rules whose next occurrence has come.
    var nextDate = Date.distantPast
    var endDate: Date?
    var isSubscription = false
    var autoConfirm = false
    var isPaused = false
    var note: String?
    var createdAt = Date.now
    var updatedAt = Date.now
    var deletedAt: Date?

    #Index<RecurringRuleRecord>([\.nextDate])

    init(id: UUID) {
        self.id = id
    }

    func update(from rule: RecurringRule) {
        name = rule.name
        kindRaw = rule.kind.rawValue
        categoryID = rule.categoryID
        amount = DecimalCoding.string(rule.amount)
        currency = rule.currency
        accountID = rule.accountID
        cardID = rule.cardID
        destinationAccountID = rule.destinationAccountID
        frequencyRaw = rule.frequency.rawValue
        interval = rule.interval
        startDate = rule.startDate
        nextDate = rule.nextDate
        endDate = rule.endDate
        isSubscription = rule.isSubscription
        autoConfirm = rule.autoConfirm
        isPaused = rule.isPaused
        note = rule.note
    }

    func toDomain() throws(DomainCorruption) -> RecurringRule {
        guard let kind = TransactionKind(rawValue: kindRaw), let frequency = RecurringFrequency(rawValue: frequencyRaw) else {
            throw DomainCorruption("Recurring rule kind/frequency \(kindRaw)/\(frequencyRaw)")
        }
        return try RecurringRule(
            id: id,
            name: name,
            kind: kind,
            categoryID: categoryID,
            amount: DecimalCoding.decimal(amount),
            currency: currency,
            accountID: accountID,
            cardID: cardID,
            destinationAccountID: destinationAccountID,
            frequency: frequency,
            interval: interval,
            startDate: startDate,
            nextDate: nextDate,
            endDate: endDate,
            isSubscription: isSubscription,
            autoConfirm: autoConfirm,
            isPaused: isPaused,
            note: note,
        )
    }
}
