import Foundation

/// Amounts are stored as their exact decimal string ("36.6243"). SwiftData and CloudKit would
/// otherwise round-trip `Decimal` through binary floating point on some paths.
enum DecimalCoding {
    static func string(_ value: Decimal) -> String {
        value.description
    }

    static func decimal(_ string: String) throws(DomainCorruption) -> Decimal {
        guard let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DomainCorruption("Invalid decimal '\(string)'")
        }
        return value
    }
}

/// A stored value that no longer maps to a domain value; surfaced as `DomainError.corruptedData`.
struct DomainCorruption: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
