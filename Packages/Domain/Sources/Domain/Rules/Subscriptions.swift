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
        let charges = transactions.filter { $0.cardID == cardID && isCharge($0) }
        let services = serviceKeys(of: charges, calendar: calendar)
        var latest: [String: (date: Date, description: String)] = [:]
        for transaction in charges {
            let folded = foldedKey(transaction.description)
            guard services.contains(folded) else { continue }
            if latest[folded].map({ transaction.date > $0.date }) ?? true {
                latest[folded] = (transaction.date, transaction.description)
            }
        }
        let charged = latest.sorted { $0.value.date > $1.value.date }
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

    /// The charges of each service, newest first: movements a recurring rule recorded grouped by
    /// that rule, and the rest grouped by card and description when `charged` would recognize them
    /// as a service. Planned movements don't count.
    public static func chargeHistories(transactions: [Transaction], calendar: Calendar) -> [[Transaction]] {
        var groups: [String: [Transaction]] = [:]
        var byCard: [UUID: [Transaction]] = [:]
        for transaction in transactions where isCharge(transaction) {
            if let ruleID = transaction.recurringID {
                groups["rule-\(ruleID)", default: []].append(transaction)
            } else if let cardID = transaction.cardID {
                byCard[cardID, default: []].append(transaction)
            }
        }
        for (cardID, charges) in byCard {
            let services = serviceKeys(of: charges, calendar: calendar)
            for transaction in charges {
                let folded = foldedKey(transaction.description)
                if services.contains(folded) {
                    groups["card-\(cardID)-\(folded)", default: []].append(transaction)
                }
            }
        }
        return groups.values.map { $0.sorted(by: isNewer) }
    }

    // MARK: - Private

    private static func isCharge(_ transaction: Transaction) -> Bool {
        transaction.kind == .expense && transaction.isConfirmed
    }

    /// Of one card's charges, the folded descriptions that look like a service: in the Subscriptions
    /// category, or charged in two different months.
    private static func serviceKeys(of charges: [Transaction], calendar: Calendar) -> Set<String> {
        var months: [String: Set<YearMonth>] = [:]
        var inCategory: Set<String> = []
        for transaction in charges {
            let folded = foldedKey(transaction.description)
            guard !folded.isEmpty else { continue }
            months[folded, default: []].insert(YearMonth(containing: transaction.date, calendar: calendar))
            if transaction.categoryID == categoryID {
                inCategory.insert(folded)
            }
        }
        return Set(months.keys.filter { inCategory.contains($0) || (months[$0]?.count ?? 0) >= 2 })
    }

    /// Newest first; the id breaks ties so the order never depends on how the list arrived.
    private static func isNewer(_ lhs: Transaction, _ rhs: Transaction) -> Bool {
        lhs.date == rhs.date ? lhs.id.uuidString > rhs.id.uuidString : lhs.date > rhs.date
    }

    /// "Apple Music" and "apple music " are the same service.
    private static func foldedKey(_ description: String) -> String {
        description.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// A subscription whose newest charge cost more than the one before it ("Netflix went up in price").
public struct PriceIncrease: Hashable, Sendable, Identifiable {
    /// How recent the newest charge must be to still be worth mentioning.
    public static let recentDays = 30

    /// The newest charge, so each increase is told once.
    public let transactionID: UUID
    /// The newest charge's description.
    public let name: String
    public let previous: Money
    public let current: Money
    /// When the newest charge happened.
    public let date: Date

    public var id: UUID {
        transactionID
    }

    public init(transactionID: UUID, name: String, previous: Money, current: Money, date: Date) {
        self.transactionID = transactionID
        self.name = name
        self.previous = previous
        self.current = current
        self.date = date
    }

    /// Each service (`Subscriptions.chargeHistories`) whose newest charge costs more than the one
    /// before it, in the same currency, and happened within `recentDays` of `now`. Newest first.
    public static func detect(in transactions: [Transaction], now: Date, calendar: Calendar) -> [Self] {
        let today = calendar.startOfDay(for: now)
        guard let since = calendar.date(byAdding: .day, value: -recentDays, to: today) else { return [] }
        return Subscriptions.chargeHistories(transactions: transactions, calendar: calendar)
            .compactMap { history -> Self? in
                guard history.count >= 2 else { return nil }
                let (newest, previous) = (history[0], history[1])
                guard newest.currency == previous.currency,
                      newest.amount > previous.amount,
                      calendar.startOfDay(for: newest.date) >= since
                else { return nil }
                return Self(
                    transactionID: newest.id,
                    name: newest.description,
                    previous: Money(previous.amount, previous.currency),
                    current: Money(newest.amount, newest.currency),
                    date: newest.date,
                )
            }
            .sorted { $0.date == $1.date ? $0.name < $1.name : $0.date > $1.date }
    }
}
