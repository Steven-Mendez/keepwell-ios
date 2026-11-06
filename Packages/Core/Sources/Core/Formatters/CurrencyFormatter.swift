import Foundation

/// Formats money the way the design writes it, independent of the device region: currency
/// symbol glued to the number ("C$8,420.00"), comma grouping, dot decimals and a true minus sign
/// ("−$709.58"). Works on `Decimal` end to end, so no amount passes through `Double`.
public struct CurrencyFormatter: Sendable {
    public enum Sign: Sendable {
        /// Minus for negatives only.
        case automatic
        /// "+" or "−" always, for lists where direction matters.
        case always
        /// Magnitude only; the caller conveys direction another way.
        case never
    }

    public init() {}

    /// `fractionDigits` defaults to 2; summaries round to whole units ("C$2,150").
    public func string(from amount: Decimal, currencyCode: String, fractionDigits: Int = 2, sign: Sign = .automatic) -> String {
        let rounded = amount.roundedHalfUp(scale: fractionDigits)
        let magnitude = Self.number(abs(rounded), fractionDigits: fractionDigits)
        let prefix = switch sign {
        case .automatic: rounded < 0 ? "−" : ""
        case .always: rounded < 0 ? "−" : "+"
        case .never: ""
        }
        return prefix + Self.symbol(for: currencyCode) + magnitude
    }

    /// Same as `string(from:)` with `sign: .always`.
    public func signedString(from amount: Decimal, currencyCode: String, fractionDigits: Int = 2) -> String {
        string(from: amount, currencyCode: currencyCode, fractionDigits: fractionDigits, sign: .always)
    }

    /// A plain grouped number without symbol ("9,443.60", "36.6243").
    public func number(_ amount: Decimal, fractionDigits: Int = 2) -> String {
        let rounded = amount.roundedHalfUp(scale: fractionDigits)
        return (rounded < 0 ? "−" : "") + Self.number(abs(rounded), fractionDigits: fractionDigits)
    }

    /// The symbol the design uses: "$" for dollar-named currencies, "C$" for córdobas, the ISO
    /// code followed by a space when there is no well-known symbol.
    public static func symbol(for currencyCode: String) -> String {
        switch currencyCode.uppercased() {
        case "USD", "MXN", "COP", "ARS", "CLP": "$"
        case "NIO": "C$"
        case "EUR": "€"
        case "GBP": "£"
        case "CRC": "₡"
        case "GTQ": "Q"
        case "HNL": "L"
        default: currencyCode.uppercased() + " "
        }
    }

    private static func number(_ magnitude: Decimal, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.groupingSize = 3
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.generatesDecimalNumbers = true
        return formatter.string(from: NSDecimalNumber(decimal: magnitude)) ?? magnitude.description
    }
}

extension Decimal {
    /// Money on screen rounds half up (0.005 → 0.01), as people expect from receipts.
    func roundedHalfUp(scale: Int) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, .plain)
        return result
    }
}
