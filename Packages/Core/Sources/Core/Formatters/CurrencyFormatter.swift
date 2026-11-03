import Foundation

/// Formats money without passing through `Double`: `Decimal.FormatStyle.Currency`
/// works on `Decimal` directly, so large or fractional amounts render exactly. Fraction digits
/// follow the currency (2 for USD/NIO, 0 for JPY).
public struct CurrencyFormatter: Sendable {
    private let locale: Locale

    public init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
    }

    public func string(from amount: Decimal, currencyCode: String) -> String {
        amount.formatted(style(for: currencyCode))
    }

    /// Always shows the sign, for lists where direction matters ("+$10.00", "-$10.00").
    public func signedString(from amount: Decimal, currencyCode: String) -> String {
        amount.formatted(style(for: currencyCode).sign(strategy: .always()))
    }

    private func style(for currencyCode: String) -> Decimal.FormatStyle.Currency {
        .currency(code: currencyCode.uppercased()).locale(locale)
    }
}
