import Foundation

/// An amount with its ISO 4217 currency. Arithmetic refuses to mix currencies: converting needs
/// an `ExchangeRate`, and silently summing USD with NIO is the bug this type exists to prevent.
public struct Money: Hashable, Sendable, Codable {
    public let amount: Decimal
    /// Uppercase ISO 4217 code ("USD", "NIO").
    public let currency: String

    public init(_ amount: Decimal, _ currency: String) {
        self.amount = amount
        self.currency = currency
    }

    public static func zero(_ currency: String) -> Self {
        Self(0, currency)
    }

    public var negated: Self {
        Self(-amount, currency)
    }

    public var isZero: Bool {
        amount == 0
    }

    public func adding(_ other: Self) throws(DomainError) -> Self {
        guard other.currency == currency else { throw .currencyMismatch(currency, other.currency) }
        return Self(amount + other.amount, currency)
    }

    public func subtracting(_ other: Self) throws(DomainError) -> Self {
        try adding(other.negated)
    }

    /// Uppercases and validates a user- or file-provided code.
    public static func normalizedCurrency(_ code: String) throws(DomainError) -> String {
        let normalized = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard ISOCurrency.isValid(normalized) else { throw .invalidCurrency(code) }
        return normalized
    }
}
