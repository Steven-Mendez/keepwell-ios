import Foundation

extension String {
    /// Capitalizes only the first letter: "noviembre de 2026" → "Noviembre de 2026".
    /// `localizedCapitalized` capitalizes every word and reads as "Noviembre De 2026" in Spanish.
    public var sentenceCased: String {
        guard let first else { return self }
        return String(first).localizedUppercase + dropFirst()
    }
}
