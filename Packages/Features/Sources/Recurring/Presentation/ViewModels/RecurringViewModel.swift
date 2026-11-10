import Core
import Domain
import Foundation
import Observation
import RecurringDomain
import SharedPresentation

/// Drives "Recurring": what subscriptions cost per month, then every rule grouped by what it is.
@MainActor
@Observable
public final class RecurringViewModel {
    public enum State: Equatable {
        case loading
        case loaded(RecurringOverview)
        case failed
    }

    /// The screen's groups, in the order they show. Empty ones are hidden.
    public enum Group: String, CaseIterable, Identifiable, Sendable {
        case subscriptions
        case bills
        case income
        case transfers

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .subscriptions: String(localized: "Subscriptions", bundle: #bundle)
            case .bills: String(localized: "Bills and other expenses", bundle: #bundle)
            case .income: String(localized: "Income", bundle: #bundle)
            case .transfers: String(localized: "Transfers", bundle: #bundle)
            }
        }

        static func of(_ rule: RecurringRule) -> Self {
            switch rule.kind {
            case .expense: rule.isSubscription ? .subscriptions : .bills
            case .income: .income
            case .transfer: .transfers
            }
        }
    }

    public struct Section: Identifiable, Equatable {
        public let group: Group
        public let rules: [RecurringRule]
        public var id: Group { group }
    }

    public private(set) var state = State.loading

    private let getOverview: any GetRecurringOverviewUseCase
    private let calendar: Calendar
    private let now: () -> Date
    let formatter = CurrencyFormatter()
    static let maskedAmount = "••••"

    public init(getOverview: any GetRecurringOverviewUseCase, calendar: Calendar = .current, now: @escaping () -> Date = { .now }) {
        self.getOverview = getOverview
        self.calendar = calendar
        self.now = now
    }

    public var overview: RecurringOverview? {
        if case let .loaded(overview) = state {
            overview
        } else {
            nil
        }
    }

    public func load() async {
        do {
            state = try await .loaded(getOverview.execute())
        } catch {
            state = .failed
        }
    }

    public var isEmpty: Bool {
        overview?.rules.isEmpty == true
    }

    /// Soonest first within each group, paused ones last.
    public var sections: [Section] {
        guard let overview else { return [] }
        let grouped = Dictionary(grouping: overview.rules, by: Group.of)
        return Group.allCases.compactMap { group in
            guard let rules = grouped[group], !rules.isEmpty else { return nil }
            return Section(group: group, rules: rules.sorted { ($0.isPaused ? 1 : 0, $0.nextDate) < ($1.isPaused ? 1 : 0, $1.nextDate) })
        }
    }

    // MARK: Header

    /// "$41.97", what live expense subscriptions cost per month in the principal currency.
    public func monthlyTotal(hidden: Bool) -> String {
        guard let overview else { return "" }
        return hidden ? Self.maskedAmount : formatter.string(overview.subscriptionsPerMonth)
    }

    /// "≈ $503.64 per year".
    public func yearlyTotal(hidden: Bool) -> String {
        guard let overview else { return "" }
        let yearly = hidden ? Self.maskedAmount : formatter.string(Money(
            overview.subscriptionsPerMonth.amount * 12,
            overview.settings.principal,
        ))
        return String(localized: "≈ \(yearly) per year", bundle: #bundle)
    }

    // MARK: Rows

    public func category(of rule: RecurringRule) -> TransactionCategory? {
        overview?.categories.first { $0.id == rule.categoryID }
    }

    /// "Every month · Tomorrow · Debit •••• 3922", or "Paused" in place of the date.
    public func subtitle(of rule: RecurringRule) -> String {
        // A rule an assistant proposed waits paused until the person resumes (confirms) or deletes it.
        let when = rule.source == .mcp && rule.isPaused
            ? String(localized: "Proposed by Claude · resume to confirm", bundle: #bundle)
            : rule.isPaused ? String(localized: "Paused", bundle: #bundle) : nextLabel(of: rule)
        return [RecurringDisplay.frequency(of: rule), when, methodName(of: rule)]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// "Today", "Tomorrow" or the day of the next occurrence; "Ended" once there are no more.
    public func nextLabel(of rule: RecurringRule) -> String {
        guard RecurringSchedule.next(1, of: rule, calendar: calendar).first != nil else {
            return String(localized: "Ended", bundle: #bundle)
        }
        return RecurringDisplay.day(rule.nextDate, today: now(), calendar: calendar)
    }

    /// The card's short name, or the account's; transfers read "Savings → Cash".
    public func methodName(of rule: RecurringRule) -> String {
        guard let overview else { return "" }
        let display = TransactionDisplay(accounts: overview.accounts, cards: overview.cards, categories: overview.categories)
        let account = overview.accounts.first { $0.id == rule.accountID }
        if rule.kind == .transfer {
            return "\(display.accountName(rule.accountID)) → \(display.accountName(rule.destinationAccountID))"
        }
        if let card = overview.cards.first(where: { $0.id == rule.cardID }), card.kind != .transfer {
            return CardDisplay.shortName(of: card)
        }
        return account.map(CardDisplay.name(of:)) ?? ""
    }

    /// Signed like a movement: "−$15.99", "+$1,500.00"; transfers carry no sign.
    public func amount(of rule: RecurringRule, hidden: Bool) -> String {
        guard !hidden else { return Self.maskedAmount }
        let sign: CurrencyFormatter.Sign = rule.kind == .transfer ? .never : .always
        return formatter.string(from: rule.kind == .expense ? -rule.amount : rule.amount, currencyCode: rule.currency, sign: sign)
    }
}
