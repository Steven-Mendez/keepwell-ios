import Foundation

/// "Cuadrar efectivo": the person counts their cash and the difference becomes a movement so the
/// balance matches what is in the wallet.
public enum CashReconciliation {
    /// `nil` when nothing changes. Less cash than recorded is an adjustment expense (HANDOFF);
    /// more cash is booked as income, since an expense can't be negative.
    public static func adjustment(
        for account: Account,
        balance: Money,
        counted: Decimal,
        date: Date,
        exchangeRate: ExchangeRate,
    ) throws(DomainError) -> Transaction? {
        guard counted >= 0 else { throw .invalidAmount }
        let difference = counted - balance.amount
        guard difference != 0 else { return nil }
        let isShortfall = difference < 0
        return Transaction(
            date: date,
            description: "Ajuste de efectivo",
            kind: isShortfall ? .expense : .income,
            categoryID: isShortfall ? TransactionCategory.otherExpenseID : TransactionCategory.otherIncomeID,
            amount: abs(difference),
            currency: balance.currency,
            accountID: account.id,
            exchangeRate: exchangeRate,
        )
    }
}
