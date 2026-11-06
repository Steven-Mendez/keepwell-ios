import Foundation

/// "1 principal = `rate` second", as the person types it in settings (e.g. 1 USD = 36.6243 NIO).
/// Each transaction keeps a copy of the rate in force when it was recorded, so editing the rate
/// later never rewrites history.
public struct ExchangeRate: Hashable, Sendable, Codable {
    public let principal: String
    public let second: String
    public let rate: Decimal

    public init(principal: String, second: String, rate: Decimal) throws(DomainError) {
        guard rate > 0 else { throw .invalidExchangeRate }
        self.principal = principal
        self.second = second
        self.rate = rate
    }

    /// Single-currency mode: the second currency is the principal and the rate is 1.
    public static func single(_ principal: String) -> Self {
        Self(uncheckedPrincipal: principal, second: principal, rate: 1)
    }

    private init(uncheckedPrincipal principal: String, second: String, rate: Decimal) {
        self.principal = principal
        self.second = second
        self.rate = rate
    }

    public var hasSecondCurrency: Bool {
        second != principal
    }

    /// Converts between the two currencies of this rate. Same-currency conversions return the
    /// amount unchanged; any other currency is outside the rate and throws.
    public func convert(_ money: Money, to currency: String) throws(DomainError) -> Money {
        if money.currency == currency {
            return money
        }
        switch (money.currency, currency) {
        case (principal, second): return Money(money.amount * rate, second)
        case (second, principal): return Money(money.amount / rate, principal)
        default: throw .currencyMismatch(money.currency, currency)
        }
    }
}
