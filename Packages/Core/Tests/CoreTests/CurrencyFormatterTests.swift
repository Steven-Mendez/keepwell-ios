import Foundation
import Testing
@testable import Core

@Suite("CurrencyFormatter")
struct CurrencyFormatterTests {
    private let formatter = CurrencyFormatter()

    private func decimal(_ string: String) throws -> Decimal {
        try #require(Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")))
    }

    @Test
    func formatsLikeTheDesign() throws {
        #expect(try formatter.string(from: decimal("11157.4625"), currencyCode: "USD") == "$11,157.46")
        #expect(try formatter.string(from: decimal("8420"), currencyCode: "NIO") == "C$8,420.00")
        #expect(try formatter.string(from: decimal("-941.3"), currencyCode: "NIO") == "−C$941.30")
        #expect(try formatter.string(from: decimal("408634.25"), currencyCode: "NIO", fractionDigits: 0) == "C$408,634")
    }

    @Test
    func keepsPrecisionBeyondDoubleRange() throws {
        let amount = try decimal("12345678901234567.89")
        #expect(formatter.string(from: amount, currencyCode: "USD") == "$12,345,678,901,234,567.89")
    }

    @Test
    func roundsHalfUp() throws {
        #expect(try formatter.string(from: decimal("378.355"), currencyCode: "USD") == "$378.36")
        #expect(try formatter.string(from: decimal("0.004"), currencyCode: "USD", sign: .always) == "+$0.00")
    }

    @Test
    func signedStringShowsDirection() throws {
        #expect(try formatter.signedString(from: decimal("3.02"), currencyCode: "USD") == "+$3.02")
        #expect(try formatter.signedString(from: decimal("-250"), currencyCode: "NIO") == "−C$250.00")
        #expect(try formatter.string(from: decimal("-250"), currencyCode: "NIO", sign: .never) == "C$250.00")
    }

    @Test
    func unknownCurrenciesUseTheirCode() throws {
        #expect(try formatter.string(from: decimal("5"), currencyCode: "chf") == "CHF 5.00")
    }

    @Test
    func plainNumbers() throws {
        #expect(try formatter.number(decimal("9443.6")) == "9,443.60")
        #expect(try formatter.number(decimal("36.6243"), fractionDigits: 4) == "36.6243")
    }
}
