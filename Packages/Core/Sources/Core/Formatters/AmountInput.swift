import Foundation

/// Parses amounts typed or pasted by people. Accepts "1234.5", "1234,5", "8,000" and "1,234.50"; rejects
/// anything else instead of `Decimal(string:)`'s habit of reading a valid prefix ("12abc" → 12).
public enum AmountInput {
    /// `nil` for invalid text. Empty text is `nil` too; callers decide whether empty means zero.
    public static func decimal(from text: String) -> Decimal? {
        var value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        if value.contains(".") {
            // A dot is the decimal mark, so commas can only be grouping separators.
            value = value.replacingOccurrences(of: ",", with: "")
        } else if value.range(of: #"^\d{1,3}(,\d{3})+$"#, options: .regularExpression) != nil {
            // "8,000" and "1,250,000": commas before groups of three digits are thousands.
            value = value.replacingOccurrences(of: ",", with: "")
        } else if value.filter({ $0 == "," }).count == 1 {
            value = value.replacingOccurrences(of: ",", with: ".")
        }
        guard value.range(of: #"^\d+(\.\d*)?$|^\.\d+$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }
}
