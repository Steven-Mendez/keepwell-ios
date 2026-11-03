import Foundation

/// HANDOFF rules 1, 3, 4 and 5: an account's balance is its opening balance plus inflows minus
/// outflows of confirmed movements, in each currency the account holds.
public enum Balances {
    /// One `Money` per currency of the account, in the order of `account.currencies`.
    public static func balance(of account: Account, transactions: [Transaction], calendar: Calendar) -> [Money] {
        let openingDay = calendar.startOfDay(for: account.openingDate)
        var totals = Dictionary(uniqueKeysWithValues: account.openingBalances.map { ($0.currency, $0.amount) })

        for transaction in transactions where transaction.isConfirmed && transaction.date >= openingDay {
            let sign = direction(of: transaction, for: account.id)
            guard sign != 0 else { continue }
            let (currency, amount) = share(of: transaction, in: account)
            totals[currency, default: 0] += Decimal(sign) * amount
        }
        return account.currencies.map { Money(totals[$0] ?? 0, $0) }
    }

    /// +1 when money enters the account, −1 when it leaves, 0 when the movement doesn't touch it.
    /// Transfers are neither expense nor income: they leave the source and enter the destination.
    static func direction(of transaction: Transaction, for accountID: UUID) -> Int {
        switch transaction.kind {
        case .expense: transaction.accountID == accountID ? -1 : 0
        case .income: transaction.accountID == accountID ? 1 : 0
        case .transfer:
            if transaction.accountID == accountID {
                -1
            } else if transaction.destinationAccountID == accountID {
                1
            } else {
                0
            }
        }
    }

    /// Which of the account's currencies the movement hits and by how much. A dual credit card
    /// books each purchase in the currency it was made in; single-currency accounts convert.
    static func share(of transaction: Transaction, in account: Account) -> (currency: String, amount: Decimal) {
        let currencies = account.currencies
        if currencies.count > 1 {
            if currencies.contains(transaction.currency) {
                return (transaction.currency, transaction.amount)
            }
            let principal = currencies[0]
            return (principal, transaction.amount(in: principal))
        }
        let currency = currencies.first ?? transaction.currency
        return (currency, transaction.amount(in: currency))
    }
}
