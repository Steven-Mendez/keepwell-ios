import Core
import Domain
import Foundation

extension CurrencyFormatter {
    public func string(_ money: Money, fractionDigits: Int = 2, sign: Sign = .automatic) -> String {
        string(from: money.amount, currencyCode: money.currency, fractionDigits: fractionDigits, sign: sign)
    }

    /// Several balances of one account joined the way cards show them ("−C$197.02 · −$16.79").
    public func joined(_ balances: [Money], fractionDigits: Int = 2) -> String {
        balances.map { string($0, fractionDigits: fractionDigits) }.joined(separator: " · ")
    }

    /// "1 USD = 36.6243 NIO".
    public func rate(_ rate: ExchangeRate) -> String {
        "1 \(rate.principal) = \(rate.rate) \(rate.second)"
    }
}
