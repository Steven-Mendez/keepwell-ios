import Foundation

/// HANDOFF rule 6: the sum of every balance converted to the principal currency with the
/// current settings rate (balances are "now", so today's rate applies).
public enum NetWorth {
    public static func total(of balances: [Money], settings: CurrencySettings) throws(DomainError) -> Money {
        let rate = settings.exchangeRate
        var total = Decimal(0)
        // A balance in a currency the settings no longer convert is left out rather than mixed in,
        // as in the forecast; the web computes it the same way.
        for balance in balances {
            guard let converted = try? rate.convert(balance, to: settings.principal) else { continue }
            total += converted.amount
        }
        return Money(total, settings.principal)
    }

    /// The currencies of non-zero balances the settings can't convert to the principal: what `total`
    /// leaves out, so the screen can say so instead of showing a total that looks complete.
    public static func excludedCurrencies(of balances: [Money], settings: CurrencySettings) -> [String] {
        let rate = settings.exchangeRate
        let left = balances.filter { $0.amount != 0 && (try? rate.convert($0, to: settings.principal)) == nil }
        return Array(Set(left.map(\.currency))).sorted()
    }

    /// The same total expressed in the second currency ("≈ C$408,634"), when there is one.
    public static func inSecondCurrency(_ total: Money, settings: CurrencySettings) -> Money? {
        guard let second = settings.second else { return nil }
        return try? settings.exchangeRate.convert(total, to: second)
    }
}
