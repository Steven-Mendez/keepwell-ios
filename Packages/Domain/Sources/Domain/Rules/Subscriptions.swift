import Foundation

/// The services charged to a card again and again, which the person has to update when the card
/// expires or is replaced. A charge counts when it's in the "Subscriptions" category, or when the same
/// description was charged in two different months: services bill monthly, a one-off purchase doesn't.
public enum Subscriptions {
    public static let categoryID = "subscriptions"

    /// Descriptions as last written, most recently charged first. Planned movements don't count.
    public static func charged(toCard cardID: UUID, transactions: [Transaction], calendar: Calendar) -> [String] {
        var months: [String: Set<YearMonth>] = [:]
        var inCategory: Set<String> = []
        var latest: [String: (date: Date, description: String)] = [:]
        for transaction in transactions where transaction.cardID == cardID && transaction.kind == .expense && transaction.isConfirmed {
            // "Apple Music" and "apple music " are the same service.
            let key = transaction.description.trimmingCharacters(in: .whitespaces)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            guard !key.isEmpty else { continue }
            months[key, default: []].insert(YearMonth(containing: transaction.date, calendar: calendar))
            if transaction.categoryID == categoryID {
                inCategory.insert(key)
            }
            if latest[key].map({ transaction.date > $0.date }) ?? true {
                latest[key] = (transaction.date, transaction.description)
            }
        }
        return latest
            .filter { key, _ in inCategory.contains(key) || (months[key]?.count ?? 0) >= 2 }
            .sorted { $0.value.date > $1.value.date }
            .map(\.value.description)
    }
}
