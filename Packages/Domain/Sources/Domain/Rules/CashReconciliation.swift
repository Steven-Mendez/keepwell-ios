import Foundation

/// "Reconcile cash": the person counts their cash and the difference becomes a movement so the
/// balance matches what is in the wallet.
public enum CashReconciliation {
    /// `nil` when nothing changes. Less cash than recorded is an adjustment expense (HANDOFF);
    /// more cash is booked as income, since an expense can't be negative. `description` is stored
    /// with the movement, so callers pass it already in the person's language.
    public static func adjustment(
        for account: Account,
        balance: Money,
        counted: Decimal,
        date: Date,
        exchangeRate: ExchangeRate,
        description: String = "Cash adjustment",
    ) throws(DomainError) -> Transaction? {
        guard counted >= 0 else { throw .invalidAmount }
        let difference = counted - balance.amount
        guard difference != 0 else { return nil }
        let isShortfall = difference < 0
        return Transaction(
            date: date,
            description: description,
            kind: isShortfall ? .expense : .income,
            categoryID: isShortfall ? TransactionCategory.otherExpenseID : TransactionCategory.otherIncomeID,
            amount: abs(difference),
            currency: balance.currency,
            accountID: account.id,
            exchangeRate: exchangeRate,
        )
    }
}
