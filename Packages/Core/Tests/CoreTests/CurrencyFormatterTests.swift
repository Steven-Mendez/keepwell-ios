import Foundation
import Testing
@testable import Core

@Suite("CurrencyFormatter")
struct CurrencyFormatterTests {
    private let formatter = CurrencyFormatter(locale: Locale(identifier: "en_US"))

    private func decimal(_ string: String) throws -> Decimal {
        try #require(Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")))
    }

    @Test
    func formatsWithCurrencyFractionDigits() throws {
        #expect(try formatter.string(from: decimal("1234.5"), currencyCode: "USD") == "$1,234.50")
    }

    @Test
    func keepsPrecisionBeyondDoubleRange() throws {
        // 17 significant digits + cents: a Double would round the last digits.
        let amount = try decimal("12345678901234567.89")
        #expect(formatter.string(from: amount, currencyCode: "USD") == "$12,345,678,901,234,567.89")
    }

    @Test
    func normalizesLowercaseCode() throws {
        #expect(try formatter.string(from: decimal("1"), currencyCode: "usd") == "$1.00")
    }

    @Test
    func signedStringShowsDirection() throws {
        #expect(try formatter.signedString(from: decimal("10"), currencyCode: "USD") == "+$10.00")
        #expect(try formatter.signedString(from: decimal("-10"), currencyCode: "USD") == "-$10.00")
    }
}
