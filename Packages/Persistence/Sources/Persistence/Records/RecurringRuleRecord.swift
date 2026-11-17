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
    /// Added in V9, one tag per line like a movement's.
    var tagsText = ""
    /// Added in V10: who created it (`RecordSource`); `nil` on older rows reads as `app`.
    var sourceRaw: String?
    /// Added in V15, like a movement's.
    var merchantID: UUID?
    var viaMerchantID: UUID?
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
        tagsText = TagsText.encode(rule.tags)
        merchantID = rule.merchantID
        viaMerchantID = rule.viaMerchantID
        // Set when created, never changed afterwards (an edit of Claude's movement stays Claude's).
        if sourceRaw == nil {
            sourceRaw = rule.source?.rawValue ?? RecordSource.app.rawValue
        }
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
            tags: TagsText.decode(tagsText),
            // `nil` means made in the app, so a rule reads back as it was saved.
            source: sourceRaw == RecordSource.mcp.rawValue ? .mcp : nil,
            merchantID: merchantID,
            viaMerchantID: viaMerchantID,
        )
    }
}
