import Foundation

/// HANDOFF rule 2, always with the rate stored on the transaction.
extension Transaction {
    private var isInSecondCurrency: Bool {
        exchangeRate.hasSecondCurrency && currency == exchangeRate.second
    }

    /// The real debit if the bank reported one; otherwise the amount, converted when it was in the
    /// second currency.
    public var principalAmount: Decimal {
        if let actualDebitedPrincipal {
            return actualDebitedPrincipal
        }
        return isInSecondCurrency ? amount / exchangeRate.rate : amount
    }

    /// The amount itself when it was in the second currency; otherwise the principal amount (real
    /// debit first) times the rate.
    public var secondAmount: Decimal {
        if isInSecondCurrency {
            return amount
        }
        return (actualDebitedPrincipal ?? amount) * exchangeRate.rate
    }

    /// The amount expressed in `currency`, which must be one of the transaction's two currencies.
    public func amount(in currency: String) -> Decimal {
        currency == exchangeRate.second && exchangeRate.hasSecondCurrency ? secondAmount : principalAmount
    }

    /// The movement in `currency`, converted with the rate it stored; `nil` when that rate doesn't
    /// reach `currency`. Each movement keeps the currencies in force when it was recorded, so after
    /// the main currency changes (say USD to EUR) its amount is no longer in the main currency:
    /// totals use this to convert it, or leave it out and say so, but never add dollars and call
    /// them euros.
    public func storedAmount(in currency: String) -> Decimal? {
        if exchangeRate.principal == currency {
            return principalAmount
        }
        if exchangeRate.hasSecondCurrency, exchangeRate.second == currency {
            return secondAmount
        }
        return nil
    }

    /// The rate the bank effectively applied (second per principal), when it reported a real debit.
    /// "Tasa del banco" on the saved screen.
    public var bankRate: Decimal? {
        guard let actualDebitedPrincipal, actualDebitedPrincipal > 0, isInSecondCurrency else { return nil }
        return amount / actualDebitedPrincipal
    }
}
