import Domain
import Foundation

/// What the movements a filtered list shows add up to, in the principal currency: the strip above
/// the list. Same rule as the web: confirmed income and spending only, so drafts and transfers
/// count in `count` but not in the money. Amounts are converted with each movement's own rate,
/// never summed across currencies.
public struct MovementTotals: Hashable, Sendable {
    public let currency: String
    public let count: Int
    public let moneyIn: Decimal
    public let moneyOut: Decimal

    public var net: Decimal { moneyIn - moneyOut }

    public init(of transactions: [Transaction], currency: String) {
        self.currency = currency
        count = transactions.count
        var moneyIn: Decimal = 0
        var moneyOut: Decimal = 0
        for transaction in transactions where transaction.isConfirmed && transaction.kind != .transfer {
            let amount = transaction.amount(in: currency)
            if transaction.kind == .income {
                moneyIn += amount
            } else {
                moneyOut += amount
            }
        }
        self.moneyIn = moneyIn
        self.moneyOut = moneyOut
    }
}
