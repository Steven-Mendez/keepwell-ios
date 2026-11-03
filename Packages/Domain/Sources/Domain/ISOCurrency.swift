import Foundation

public enum ISOCurrency {
    /// Taken from Foundation's ISO 4217 table rather than hard-coded, so new codes arrive with OS updates.
    private static let codes: Set<String> = Set(Locale.Currency.isoCurrencies.map(\.identifier))

    /// Case-sensitive on purpose: callers normalize first, so stored codes are always uppercase.
    public static func isValid(_ code: String) -> Bool {
        codes.contains(code)
    }
}
