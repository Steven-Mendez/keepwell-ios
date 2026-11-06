import Foundation

// The scalar encodings the backup file shares with the web app.

/// Exact decimal text with a dot and no exponent or grouping, which both Swift and JavaScript
/// decimal libraries read without going through a binary double.
enum PortableDecimal {
    static func string(_ value: Decimal) -> String {
        value.description
    }

    static func decimal(_ text: String) throws(DomainError) -> Decimal {
        // `Decimal(string:)` alone accepts "12abc" as 12, so the shape is checked first.
        guard text.wholeMatch(of: /-?[0-9]+(\.[0-9]+)?/) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
        else { throw .corruptedData("Invalid decimal '\(text)'") }
        return value
    }
}

/// Lowercase, as the web writes them, so the same id is the same string on both platforms.
enum PortableID {
    static func string(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }

    static func uuid(_ text: String) throws(DomainError) -> UUID {
        guard let id = UUID(uuidString: text) else { throw .corruptedData("Invalid id '\(text)'") }
        return id
    }
}

enum PortableDate {
    static let withMilliseconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let wholeSeconds = Date.ISO8601FormatStyle()

    /// Accepts both forms: JavaScript always writes milliseconds, older Swift writers never do.
    static func parse(_ text: String) -> Date? {
        (try? withMilliseconds.parse(text)) ?? (try? wholeSeconds.parse(text))
    }
}
