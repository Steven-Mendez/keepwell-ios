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

    public init(
        settings: CurrencySettings,
        rules: [RecurringRule],
        accounts: [Account],
        cards: [Card],
        categories: [TransactionCategory],
        recorded: [Transaction],
    ) {
        self.settings = settings
        self.rules = rules
        self.accounts = accounts
        self.cards = cards
        self.categories = categories
        self.recorded = recorded
        subscriptionsPerMonth = Self.monthlyTotal(of: rules.filter { $0.isSubscription && $0.kind == .expense }, settings: settings)
    }

    public func rule(_ id: UUID) -> RecurringRule? {
        rules.first { $0.id == id }
    }

    /// Paused subscriptions don't cost anything this month. Each rule is converted with today's
    /// rate; one in a currency outside the rate can't be added and is left out.
    static func monthlyTotal(of rules: [RecurringRule], settings: CurrencySettings) -> Money {
        let rate = settings.exchangeRate
        let total = rules.filter { !$0.isPaused }.reduce(Decimal(0)) { sum, rule in
            let monthly = Money(RecurringSchedule.monthlyEquivalent(of: rule), rule.currency)
            guard let converted = try? rate.convert(monthly, to: settings.principal) else { return sum }
            return sum + converted.amount
        }
        return Money(total, settings.principal)
    }
}
