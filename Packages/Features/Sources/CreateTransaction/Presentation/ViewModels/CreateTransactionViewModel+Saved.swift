import CreateTransactionDomain
import Domain
import Foundation
import SharedPresentation

/// Copy for the review and saved steps.
extension CreateTransactionViewModel {
    public struct Row: Hashable, Sendable {
        public let label: String
        public let value: String
    }

    /// "−C$879" next to the category question.
    public var amountSummary: String {
        sign + formatter.string(Money(amount, currency), fractionDigits: amount == amount.rounded(scale: 0) ? 0 : 2)
    }

    /// "−C$879.00".
    public var reviewAmount: String {
        sign + formatter.string(Money(amount, currency))
    }

    /// The conversion the app would use, as the real-debit placeholder.
    public var suggestedDebit: String {
        guard let currencies = context?.currencies,
              let converted = try? currencies.exchangeRate.convert(Money(amount, currency), to: currencies.principal)
        else { return "0.00" }
        return formatter.number(converted.amount)
    }

    public func balanceLabel(of account: Account) -> String {
        formatter.joined(context?.balances[account.id] ?? [], fractionDigits: 2)
    }

    /// Debit, rate and new balance.
    public func savedRows(_ saved: SavedTransaction) -> [Row] {
        let transaction = saved.transaction
        let currencyOfAccount = saved.account.currencies.contains(transaction.currency)
            ? transaction.currency
            : saved.account.currencies.first ?? transaction.currency
        let moved = Money(transaction.amount(in: currencyOfAccount), currencyOfAccount)
        let accountName = CardDisplay.name(of: saved.account)
        let accountLabel = transaction.kind == .income
            ? String(localized: "Credited to \(accountName)", bundle: #bundle)
            : String(localized: "Debited from \(accountName)", bundle: #bundle)
        var rows = [Row(
            label: accountLabel,
            value: formatter.string(moved, sign: transaction.kind == .income ? .always : .never).withMinus(transaction.kind != .income),
        )]
        let rate = transaction.exchangeRate
        if rate.hasSecondCurrency {
            if let bankRate = transaction.bankRate {
                rows.append(Row(
                    label: String(localized: "Bank rate", bundle: #bundle),
                    value: "\(formatter.number(bankRate)) \(rate.second)",
                ))
            } else {
                rows.append(Row(label: String(localized: "Rate used", bundle: #bundle), value: "\(rate.rate) \(rate.second)"))
            }
        }
        rows.append(Row(label: String(localized: "New balance", bundle: #bundle), value: formatter.joined(saved.newBalances)))
        return rows
    }

    /// "Restaurants in November · $24.28".
    public func categoryTotalRow(_ saved: SavedTransaction) -> Row? {
        guard let total = saved.categoryMonthTotal, let category else { return nil }
        let month = saved.transaction.date.formatted(.dateTime.month(.wide))
        let categoryName = CategoryDisplay.name(of: category)
        return Row(label: String(localized: "\(categoryName) in \(month)", bundle: #bundle), value: formatter.string(total))
    }
}

extension String {
    fileprivate func withMinus(_ applies: Bool) -> String {
        applies ? "−" + self : self
    }
}
