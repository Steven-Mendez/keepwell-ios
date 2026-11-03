import Domain
import Foundation
import SwiftData
import TransactionsDomain

/// Defaults on every property and no unique constraints: required by CloudKit sync (see `KeepwellSchema`).
@Model
public final class TransactionRecord {
    public var id = UUID()
    /// Canonical decimal string ("1234.56"), not `Decimal`: SwiftData/Core Data don't guarantee a
    /// lossless `Decimal` round-trip through CloudKit, and a ledger must never drift by a cent.
    public var amountString: String = "0"
    public var currency: String = "USD"
    public var kindRaw: String = TransactionKind.expense.rawValue
    public var statusRaw: String = TransactionStatus.confirmed.rawValue
    public var categoryID: String = ""
    /// Snapshot of the name at save time, so the row still reads correctly if the category is
    /// renamed or deleted later.
    public var categoryName: String = ""
    public var date = Date.distantPast
    public var note: String?

    public init(
        id: UUID,
        amountString: String,
        currency: String,
        kindRaw: String,
        statusRaw: String,
        categoryID: String,
        categoryName: String,
        date: Date,
        note: String?,
    ) {
        self.id = id
        self.amountString = amountString
        self.currency = currency
        self.kindRaw = kindRaw
        self.statusRaw = statusRaw
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.date = date
        self.note = note
    }
}

// MARK: - Mapping

/// `Decimal.description` always uses "." regardless of the device locale; parsing must match.
private let canonicalLocale = Locale(identifier: "en_US_POSIX")

extension TransactionRecord {
    public func toDomain() throws(DomainError) -> Transaction {
        guard let amount = Decimal(string: amountString, locale: canonicalLocale) else {
            throw .corruptedData("Transaction \(id): amount '\(amountString)'")
        }
        guard let kind = TransactionKind(rawValue: kindRaw) else {
            throw .corruptedData("Transaction \(id): kind '\(kindRaw)'")
        }
        guard let status = TransactionStatus(rawValue: statusRaw) else {
            throw .corruptedData("Transaction \(id): status '\(statusRaw)'")
        }
        return Transaction(
            id: id,
            amount: amount,
            currency: currency,
            kind: kind,
            category: TransactionCategory(id: categoryID, name: categoryName, kind: kind),
            date: date,
            note: note,
            status: status,
        )
    }
}

extension Transaction {
    public func toEntity() -> TransactionRecord {
        TransactionRecord(
            id: id,
            amountString: amount.description,
            currency: currency,
            kindRaw: kind.rawValue,
            statusRaw: status.rawValue,
            categoryID: category.id,
            categoryName: category.name,
            date: date,
            note: note,
        )
    }
}
