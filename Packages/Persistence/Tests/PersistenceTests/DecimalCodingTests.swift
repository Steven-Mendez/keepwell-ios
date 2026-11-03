import Foundation
import Testing
@testable import Persistence

@Suite("Decimal coding")
struct DecimalCodingTests {
    @Test(arguments: ["36.6243", "0.01", "-941.3", "11157.4625", "1e-4"])
    func roundTripsExactly(text: String) throws {
        let value = try #require(Decimal(string: text))
        #expect(try DecimalCoding.decimal(DecimalCoding.string(value)) == value)
    }

    @Test
    func rejectsGarbage() {
        #expect(throws: DomainCorruption.self) { try DecimalCoding.decimal("abc") }
    }
}
