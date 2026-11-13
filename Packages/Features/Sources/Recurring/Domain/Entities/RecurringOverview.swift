import Domain
import Foundation

/// Everything the recurring screen and the rule editor show: the rules, what they pay with, the
/// movements they recorded and what subscriptions cost per month.
public struct RecurringOverview: Hashable, Sendable {
    public let settings: CurrencySettings
    /// In the order they were created.
    public let rules: [RecurringRule]
    public let accounts: [Account]
    public let cards: [Card]
    public let categories: [TransactionCategory]
    /// Movements recorded by a rule, newest first.
    public let recorded: [Transaction]
    /// Live expense subscriptions per month, in the principal currency, unrounded.
    public let subscriptionsPerMonth: Money
    /// Live expense subscriptions the total leaves out because their currency can't be converted,
    /// by currency code. Empty when the total counts them all.
    public let excludedSubscriptions: [UnconvertedSubscriptions]

    public init(
        settings: CurrencySettings,
        rules: [RecurringRule],
        accounts: [Account],
        cards: [Card],
        categories: [TransactionCategory],
        recorded: [Transaction],
        calendar: Calendar = .current,
    ) {
        self.settings = settings
        self.rules = rules
        self.accounts = accounts
        self.cards = cards
        self.categories = categories
        self.recorded = recorded
        let total = Self.monthlyTotal(
            of: rules.filter { $0.isSubscription && $0.kind == .expense },
            settings: settings,
            calendar: calendar,
        )
        subscriptionsPerMonth = total.perMonth
        excludedSubscriptions = total.excluded
    }

    public func rule(_ id: UUID) -> RecurringRule? {
        rules.first { $0.id == id }
    }

    /// Paused and finished subscriptions don't cost anything this month. Each rule is converted
    /// with today's rate; one in a currency outside the rate can't be added, so it is left out and
    /// counted under its currency for the screen to say the total is incomplete.
    static func monthlyTotal(
        of rules: [RecurringRule],
        settings: CurrencySettings,
        calendar: Calendar,
    ) -> (perMonth: Money, excluded: [UnconvertedSubscriptions]) {
        let rate = settings.exchangeRate
        var total = Decimal(0)
        var excluded: [String: Int] = [:]
        for rule in rules where RecurringSchedule.isActive(rule, calendar: calendar) {
            let monthly = Money(RecurringSchedule.monthlyEquivalent(of: rule), rule.currency)
            if let converted = try? rate.convert(monthly, to: settings.principal) {
                total += converted.amount
            } else {
                excluded[rule.currency, default: 0] += 1
            }
        }
        let unconverted = excluded.keys.sorted().map { UnconvertedSubscriptions(currency: $0, count: excluded[$0] ?? 0) }
        return (Money(total, settings.principal), unconverted)
    }
}
