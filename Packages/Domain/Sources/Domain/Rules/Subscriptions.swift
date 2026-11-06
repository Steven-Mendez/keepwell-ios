import Foundation

/// The services charged to a card again and again, which the person has to update when the card
/// expires or is replaced. A charge counts when it's in the "Subscriptions" category, or when the same
/// description was charged in two different months: services bill monthly, a one-off purchase doesn't.
/// Recurring rules marked as subscriptions and paid with the card count too, even before they charge.
public enum Subscriptions {
    public static let categoryID = "subscriptions"

    /// Descriptions as last written, most recently charged first, then subscription rules not
    /// charged yet. Planned movements don't count.
    public static func charged(
        toCard cardID: UUID,
        transactions: [Transaction],
        rules: [RecurringRule] = [],
        calendar: Calendar,
    ) -> [String] {
        var months: [String: Set<YearMonth>] = [:]
        var inCategory: Set<String> = []
        var latest: [String: (date: Date, description: String)] = [:]
        for transaction in transactions where transaction.cardID == cardID && transaction.kind == .expense && transaction.isConfirmed {
            let folded = foldedKey(transaction.description)
            guard !folded.isEmpty else { continue }
            months[folded, default: []].insert(YearMonth(containing: transaction.date, calendar: calendar))
            if transaction.categoryID == categoryID {
                inCategory.insert(folded)
            }
            if latest[folded].map({ transaction.date > $0.date }) ?? true {
                latest[folded] = (transaction.date, transaction.description)
            }
        }
        let charged = latest
            .filter { key, _ in inCategory.contains(key) || (months[key]?.count ?? 0) >= 2 }
            .sorted { $0.value.date > $1.value.date }
        var seen = Set(charged.map(\.key))
        var names = charged.map(\.value.description)
        for rule in rules where rule.isSubscription && rule.cardID == cardID {
            let folded = foldedKey(rule.name)
            if !folded.isEmpty, seen.insert(folded).inserted {
                names.append(rule.name)
            }
        }
        return names
    }

    /// "Apple Music" and "apple music " are the same service.
    private static func foldedKey(_ description: String) -> String {
        description.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
