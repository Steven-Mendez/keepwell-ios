import Foundation

/// Which movements a list looks at: everything or one account. A bank account is its one card, so
/// narrowing by card would show the same list; a credit card's additionals have their own screen.
public enum TransactionScope: Hashable, Sendable {
    case all
    case account(UUID)

    /// An account sees what left it and, for transfers, what arrived in it, so its list reads the
    /// way its balance moves.
    public func includes(_ transaction: Transaction) -> Bool {
        switch self {
        case .all: true
        case let .account(id): transaction.accountID == id || transaction.destinationAccountID == id
        }
    }
}
