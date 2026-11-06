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

    /// The rate the bank effectively applied (second per principal), when it reported a real debit.
    /// "Tasa del banco" on the saved screen.
    public var bankRate: Decimal? {
        guard let actualDebitedPrincipal, actualDebitedPrincipal > 0, isInSecondCurrency else { return nil }
        return amount / actualDebitedPrincipal
    }
}
