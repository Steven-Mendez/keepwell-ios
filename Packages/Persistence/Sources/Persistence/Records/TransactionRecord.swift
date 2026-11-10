import Domain
import Foundation
import SwiftData

@Model
public final class TransactionRecord: AuditedRecord {
    public var id = UUID()
    /// Indexed: every screen filters movements by date range.
    var date = Date.distantPast
    var statusRaw = TransactionStatus.confirmed.rawValue
    var descriptionText = ""
    var kindRaw = TransactionKind.expense.rawValue
    var categoryID: String?
    var amount = "0"
    var currency = ""
    var accountID = UUID()
    var cardID: UUID?
    var destinationAccountID: UUID?
    var actualDebitedPrincipal: String?
    var ratePrincipal = ""
    var rateSecond = ""
    var rate = "1"
    var isShared = false
    var note: String?
    /// Added in V5; rows migrated from V4 get the migration's time, since earlier ones weren't kept.
    var createdAt = Date.now
    var updatedAt = Date.now
    var deletedAt: Date?
    /// Added in V6: the recurring rule that recorded it.
    var recurringID: UUID?
    /// Added in V9: the normalized tags, one per line (a tag never holds whitespace). Text rather
    /// than an array attribute, which CloudKit mirroring would store as an opaque blob anyway.
    var tagsText = ""
    /// Added in V10: who created it (`RecordSource`); `nil` on older rows reads as `app`.
    var sourceRaw: String?

    #Index<TransactionRecord>([\.date])

    init(id: UUID) {
        self.id = id
    }

    func update(from transaction: Transaction) {
        date = transaction.date
        statusRaw = transaction.status.rawValue
        descriptionText = transaction.description
        kindRaw = transaction.kind.rawValue
        categoryID = transaction.categoryID
        amount = DecimalCoding.string(transaction.amount)
        currency = transaction.currency
        accountID = transaction.accountID
        cardID = transaction.cardID
        destinationAccountID = transaction.destinationAccountID
        actualDebitedPrincipal = transaction.actualDebitedPrincipal.map(DecimalCoding.string)
        ratePrincipal = transaction.exchangeRate.principal
        rateSecond = transaction.exchangeRate.second
        rate = DecimalCoding.string(transaction.exchangeRate.rate)
        isShared = transaction.isShared
        note = transaction.note
        recurringID = transaction.recurringID
        tagsText = TagsText.encode(transaction.tags)
        // Set when created, never changed afterwards (an edit of Claude's movement stays Claude's).
        if sourceRaw == nil {
            sourceRaw = transaction.source.rawValue
        }
    }

    func toDomain() throws(DomainCorruption) -> Transaction {
        guard let status = TransactionStatus(rawValue: statusRaw), let kind = TransactionKind(rawValue: kindRaw) else {
            throw DomainCorruption("Transaction status/kind \(statusRaw)/\(kindRaw)")
        }
        let exchangeRate: ExchangeRate
        do {
            exchangeRate = try ExchangeRate(principal: ratePrincipal, second: rateSecond, rate: DecimalCoding.decimal(rate))
        } catch let error as DomainCorruption {
            throw error
        } catch {
            throw DomainCorruption("Exchange rate \(rate)")
        }
        return try Transaction(
            id: id,
            date: date,
            status: status,
            description: descriptionText,
            kind: kind,
            categoryID: categoryID,
            amount: DecimalCoding.decimal(amount),
            currency: currency,
            accountID: accountID,
            cardID: cardID,
            destinationAccountID: destinationAccountID,
            actualDebitedPrincipal: actualDebitedPrincipal.map { value throws(DomainCorruption) in try DecimalCoding.decimal(value) },
            exchangeRate: exchangeRate,
            isShared: isShared,
            note: note,
            recurringID: recurringID,
            tags: TagsText.decode(tagsText),
            source: sourceRaw.flatMap(RecordSource.init(rawValue:)) ?? .app,
        )
    }
}

/// Tags as one line each, the way movements, recurring rules and categorization rules store them.
enum TagsText {
    static func encode(_ tags: [String]) -> String {
        tags.joined(separator: "\n")
    }

    static func decode(_ text: String) -> [String] {
        text.split(separator: "\n").map(String.init)
    }
}
