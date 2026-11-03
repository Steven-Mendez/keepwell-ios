import Foundation
import Testing
@testable import Core

@Suite("Amount input")
struct AmountInputTests {
    @Test(arguments: [
        ("1234.5", "1234.5"), ("1234,5", "1234.5"), ("1,234.50", "1234.5"), ("36.6243", "36.6243"),
        (" 879 ", "879"), (".5", "0.5"), ("10.", "10"), ("8,000", "8000"), ("1,250,000", "1250000"), ("12,50", "12.5"),
    ])
    func acceptsCommonFormats(text: String, expected: String) {
        #expect(AmountInput.decimal(from: text) == Decimal(string: expected))
    }

    @Test(arguments: ["", "abc", "12abc", "-1", "1.2.3", "1,2,3", "1e5"])
    func rejectsInvalidText(text: String) {
        #expect(AmountInput.decimal(from: text) == nil)
    }
}
