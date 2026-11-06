import Foundation

/// What a credit card's next payment asks for: the debt its statement closed with, minus what was
/// paid into the card since. Shared with the web app so both forecast the same payment.
public enum CardStatement {
    /// In the principal currency at the settings rate, never below zero. With a cutoff day the
    /// statement is the debt through the last cutoff before `due` (`BillingCycle.statementCutoff`),
    /// less payments and refunds that reached the card after it; without one, the whole debt today.
    public static func amountDue(
        on due: Date,
        account: Account,
        transactions: [Transaction],
        settings: CurrencySettings,
        calendar: Calendar,
    ) -> Decimal {
        let rate = settings.exchangeRate
        let principal = { (money: Money) in (try? rate.convert(money, to: settings.principal).amount) ?? 0 }
        guard let cutoffDay = account.creditTerms?.cutoffDay,
              let cutoff = BillingCycle.statementCutoff(before: due, cutoffDay: cutoffDay, calendar: calendar),
              let closed = calendar.date(byAdding: .day, value: 1, to: cutoff)
        else {
            let debt = Balances.balance(of: account, transactions: transactions, calendar: calendar).reduce(0) { $0 + principal($1) }
            return max(-debt, 0)
        }
        let statement = Balances.balance(of: account, transactions: transactions.filter { $0.date < closed }, calendar: calendar)
        let owed = -statement.reduce(0) { $0 + principal($1) }
        var paid = Decimal(0)
        for transaction in transactions
            where transaction.isConfirmed && transaction.date >= closed && Balances.direction(of: transaction, for: account.id) > 0
        {
            let (currency, amount) = Balances.share(of: transaction, in: account)
            paid += principal(Money(amount, currency))
        }
        return max(owed - paid, 0)
    }
}
