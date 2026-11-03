import Domain
import Foundation

/// `amount` is always positive; `kind` carries the direction. Keeping the sign out of the amount
/// means a mis-signed value can't silently flip an expense into income.
public struct Transaction: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let amount: Decimal
    /// ISO 4217, uppercase ("USD", "NIO").
    public let currency: String
    public let kind: TransactionKind
    public let category: TransactionCategory
    public let date: Date
    public let note: String?
    /// `planned` movements don't count toward balances or summaries until confirmed (HANDOFF rule 1).
    public let status: TransactionStatus

    public init(
        id: UUID = UUID(),
        amount: Decimal,
        currency: String,
        kind: TransactionKind,
        category: TransactionCategory,
        date: Date,
        note: String? = nil,
        status: TransactionStatus = .confirmed,
    ) {
        self.id = id
        self.amount = amount
        self.currency = currency
        self.kind = kind
        self.category = category
        self.date = date
        self.note = note
        self.status = status
    }
}
