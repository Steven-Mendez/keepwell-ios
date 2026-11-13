import Foundation

/// A merchant or service Keepwell knows, so its row can show the brand's logo. The table
/// (`Resources/brands.json`) is a verbatim copy of keepwell-web's
/// `src/lib/presentation/brands/brands.json`, whose tests fail when the two diverge. Only `domain`
/// ever leaves the device, and only for a brand of this table.
public struct Brand: Decodable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let domain: String
    /// Normalized word sequences that name the brand anywhere in a text.
    public let aliases: [String]
    /// Normalized words too short or too common to match unless they are the whole text ("max").
    public let exactAliases: [String]

    /// The first letter or digit, which the badge shows before (or instead of) the logo.
    public var monogram: String {
        name.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? "·"
    }
}

/// `brandFor` of keepwell-web, with the same rules and the same shared cases.
public enum BrandCatalog {
    public static let brands: [Brand] = {
        struct Table: Decodable { let brands: [Brand] }
        guard let url = Bundle.module.url(forResource: "brands", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode(Table.self, from: data)
        else { return [] }
        return table.brands
    }()

    /// A single-word alias this short only matches the whole text, even when the table doesn't say so.
    private static let shortAliasLength = 4

    /// Lowercase, accents and other marks removed, anything but letters and digits as a space, and
    /// spaces collapsed. Works on the same Unicode categories as the web's `\p{M}`, `\p{L}` and `\p{N}`.
    public static func normalize(_ text: String) -> String {
        var normalized = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in text.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark:
                continue
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .decimalNumber, .letterNumber, .otherNumber:
                if pendingSpace, !normalized.isEmpty {
                    normalized.append(" ")
                }
                pendingSpace = false
                normalized.append(scalar)
            default:
                pendingSpace = true
            }
        }
        return String(normalized)
    }

    /// The brand a rule's name or a movement's description names, or `nil`. Aliases match whole
    /// words, never part of one ("max" is not in "Maxi Palí"); when several match, the longest
    /// alias wins ("Uber Eats" over "Uber"), then the table's order; a short or common one-word
    /// alias only matches the entire text.
    public static func brand(for text: String, in brands: [Brand] = brands) -> Brand? {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return nil }
        let words = normalized.split(separator: " ").map(String.init)
        var best: (brand: Brand, words: Int, length: Int)?
        for brand in brands {
            for alias in brand.aliases + brand.exactAliases {
                let aliasWords = alias.split(separator: " ").map(String.init)
                let wholeTextOnly = brand.exactAliases.contains(alias)
                    || (aliasWords.count == 1 && alias.count < shortAliasLength)
                let matches = wholeTextOnly ? alias == normalized : containsRun(words, aliasWords)
                guard matches else { continue }
                if let current = best,
                   aliasWords.count < current.words || (aliasWords.count == current.words && alias.count <= current.length)
                {
                    continue
                }
                best = (brand, aliasWords.count, alias.count)
            }
        }
        return best?.brand
    }

    private static func containsRun(_ words: [String], _ run: [String]) -> Bool {
        guard !run.isEmpty, run.count <= words.count else { return false }
        return (0 ... words.count - run.count).contains { start in
            words[start ..< start + run.count].elementsEqual(run)
        }
    }
}
