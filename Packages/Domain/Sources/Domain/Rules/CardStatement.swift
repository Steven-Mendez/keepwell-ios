import Foundation

/// What a credit card's next payment asks for: the debt its statement closed with, minus what was
/// paid into the card since. Shared with the web app so both forecast the same payment.
public enum CardStatement {
    /// In the principal currency's cents at the settings rate, never below zero. With a cutoff day the
    /// statement is the debt through the last cutoff before `due` (`BillingCycle.statementCutoff`),
    /// less payments and refunds that reached the card after it; without one, the whole debt today.
    ///
    /// A card opened after that cutoff has its opening debt walked back to it
    /// (`Balances.balance(of:before:)`): what it bought between the cutoff and the opening day
    /// belongs to the next statement, not this one.
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
            return cents(max(-debt, 0))
        }
        let statement = Balances.balance(of: account, before: closed, transactions: transactions, calendar: calendar)
        let owed = -statement.reduce(0) { $0 + principal($1) }
        var paid = Decimal(0)
        for transaction in transactions
            where transaction.isConfirmed && transaction.date >= closed && Balances.direction(of: transaction, for: account.id) > 0
        {
            let (currency, amount) = Balances.share(of: transaction, in: account)
            paid += principal(Money(amount, currency))
        }
        return cents(max(owed - paid, 0))
    }

    /// Amounts converted one by one don't add up to the last digit, so a statement paid in full would
    /// still owe a sliver. Nobody owes less than a cent: half up, as amounts are shown.
    private static func cents(_ amount: Decimal) -> Decimal {
        amount.rounded(scale: 2, mode: .plain)
    }
}
