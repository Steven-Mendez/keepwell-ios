import Foundation

// What a movement may point at, shared by every path that builds one from the person's choices:
// the create flow and the recurring rules that record movements later. Kept in the kernel so both
// refuse exactly the same things.

extension Transaction {
    /// Movements are recorded in the principal or the second currency, the only two the rate converts.
    public static func checkCurrency(_ currency: String, currencies: CurrencySettings) throws(DomainError) {
        guard currency == currencies.principal || currency == currencies.second else {
            throw .invalidCurrency(currency)
        }
    }

    /// A transfer lands in another account that exists.
    public static func checkDestination(_ destination: UUID?, from accountID: UUID, accounts: [Account]) throws(DomainError) {
        guard let destination, destination != accountID, accounts.contains(where: { $0.id == destination }) else {
            throw .invalidTransferDestination
        }
    }

    /// Expenses and income go in an existing category of their own kind, which is returned.
    @discardableResult
    public static func checkCategory(
        _ categoryID: String?,
        kind: TransactionKind,
        categories: [TransactionCategory],
    ) throws(DomainError) -> TransactionCategory {
        guard let found = categories.first(where: { $0.id == categoryID }) else {
            throw .notFound(UUID(uuid: UUID_NULL))
        }
        guard found.kind == kind else { throw .categoryKindMismatch(expected: kind, actual: found.kind) }
        return found
    }
}
