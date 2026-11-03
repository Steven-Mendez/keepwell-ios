import Foundation

/// Which movements a list looks at: everything, one account or one card.
public enum TransactionScope: Hashable, Sendable {
    case all
    case account(UUID)
    case card(UUID)

    /// An account sees what left it and, for transfers, what arrived in it, so its list reads the
    /// way its balance moves. A card only sees what it paid.
    public func includes(_ transaction: Transaction) -> Bool {
        switch self {
        case .all: true
        case let .account(id): transaction.accountID == id || transaction.destinationAccountID == id
        case let .card(id): transaction.cardID == id
        }
    }
}
