import Foundation

/// Labels a movement carries besides its category ("#viaje-mexico", "#boda"), to follow a trip or
/// an event across categories. Stored normalized, so "#Viaje México" and "viaje méxico" are the
/// same tag. The web app ports these rules one to one (`src/lib/domain/tags.ts`).
public enum Tags {
    /// Counted in Unicode scalars, which JavaScript's `[...text]` also counts, so both apps cut a
    /// long tag at the same place.
    public static let maxLength = 32

    /// The stored form of a tag: trimmed, without the leading "#", lowercased, spaces turned into
    /// "-", at most `maxLength` long. Accents stay ("méxico"): they are part of the word. `nil` when
    /// nothing is left.
    public static func normalized(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasPrefix("#") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        text = text.lowercased().precomposedStringWithCanonicalMapping
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: "-")
        text = String(String.UnicodeScalarView(text.unicodeScalars.prefix(maxLength)))
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "-")).nilIfEmpty
    }

    /// Each tag normalized once, in the order first given; blanks and repeats dropped.
    public static func normalized(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap(normalized).filter { seen.insert($0).inserted }
    }

    /// How a CSV row writes them: "#viaje-mexico #boda", or "" without any.
    public static func csvField(_ tags: [String]) -> String {
        tags.map { "#\($0)" }.joined(separator: " ")
    }

    /// The tags a CSV cell lists, split on spaces or commas ("#boda, #viaje-mexico"), normalized.
    public static func parsed(csvField text: String) -> [String] {
        normalized(text.split { $0.isWhitespace || $0 == "," }.map(String.init))
    }

    /// `tags` with `added` after them, each once.
    public static func merging(_ tags: [String], with added: [String]) -> [String] {
        normalized(tags + added)
    }

    /// Every tag used, most used first, then alphabetically: the editor's suggestions.
    public static func usage(in transactions: [Transaction]) -> [String] {
        var counts: [String: Int] = [:]
        for transaction in transactions {
            for tag in transaction.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }

    /// Up to `limit` used tags the person may mean while typing `text`: those containing it, the
    /// ones already on the movement left out.
    public static func suggestions(from usage: [String], typing text: String, excluding chosen: [String], limit: Int = 8) -> [String] {
        let needle = normalized(text) ?? ""
        return Array(usage.filter { !chosen.contains($0) && (needle.isEmpty || $0.contains(needle)) }.prefix(limit))
    }

    /// The tag a search asks for: "#boda" (or "# Boda") narrows the list to that tag. `nil` for any
    /// other search.
    public static func searched(in query: String) -> String? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("#") else { return nil }
        return normalized(text)
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
