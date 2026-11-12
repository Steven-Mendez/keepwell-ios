import Core
import Domain
import Foundation
import RecurringDomain
import SharedPresentation

/// The editor's options (kinds, methods, accounts, categories, frequencies) and the rule's detail.
extension RecurringRuleEditorViewModel {
    // MARK: Choices

    public var title: String {
        if isEditing {
            return String(localized: "Edit recurring", bundle: #bundle)
        }
        return isNewSubscription
            ? String(localized: "New subscription", bundle: #bundle)
            : String(localized: "New recurring", bundle: #bundle)
    }

    public var kindOptions: [(value: TransactionKind, title: String)] {
        [
            (.expense, String(localized: "Expense", bundle: #bundle)),
            (.income, String(localized: "Income", bundle: #bundle)),
            (.transfer, String(localized: "Transfer", bundle: #bundle)),
        ]
    }

    public var currencyOptions: [String] {
        guard let settings = overview?.settings else { return [currency] }
        return [settings.second, settings.principal].compactMap(\.self)
    }

    public var amount: Decimal {
        AmountInput.decimal(from: amountText) ?? 0
    }

    /// Every way money can leave (or arrive): each plastic and transfer channel, and accounts
    /// without any (cash). Transfers move between accounts, so they list the accounts that can send.
    public var methodOptions: [MethodOption] {
        guard let overview else { return [] }
        return overview.accounts.flatMap { account -> [MethodOption] in
            let cards = overview.cards.filter { $0.accountID == account.id }
            if kind == .transfer {
                guard account.kind != .credit else { return [] }
                let channel = cards.first { $0.kind == .transfer }
                return [MethodOption(
                    method: channel.map { .card($0.id) } ?? .account(account.id),
                    title: CardDisplay.name(of: account),
                    subtitle: account.currencies.formatted(.list(type: .and)),
                    thumbnail: account.kind == .cash ? .cash : .transfer,
                )]
            }
            guard !cards.isEmpty else {
                return [MethodOption(method: .account(account.id), title: CardDisplay.name(of: account), subtitle: nil, thumbnail: .cash)]
            }
            return cards.map { card in
                MethodOption(
                    method: .card(card.id),
                    title: CardDisplay.methodTitle(card, account: account),
                    subtitle: card.kind == .transfer ? nil : CardDisplay.name(of: account),
                    thumbnail: card.kind == .transfer ? .transfer : .card(card.color),
                )
            }
        }
    }

    public var methodTitle: String? {
        methodOptions.first { $0.method == method }?.title
    }

    public var sourceAccountID: UUID? {
        switch method {
        case let .card(id): overview?.cards.first { $0.id == id }?.accountID
        case let .account(id): id
        case nil: nil
        }
    }

    /// Any other account; paying into a credit card is a transfer too.
    public var destinationOptions: [Account] {
        overview?.accounts.filter { $0.id != sourceAccountID } ?? []
    }

    public var destinationTitle: String? {
        destinationOptions.first { $0.id == destinationAccountID }.map(CardDisplay.name(of:))
    }

    public var categoryOptions: [TransactionCategory] {
        TransactionCategory.ordered(overview?.categories ?? []).filter { $0.kind == kind }
    }

    public var category: TransactionCategory? {
        overview?.categories.first { $0.id == categoryID }
    }

    public func selectCategory(_ id: String) {
        categoryID = id
    }

    public func selectMethod(_ method: Method) {
        self.method = method
        if destinationAccountID == sourceAccountID {
            destinationAccountID = nil
        }
    }

    public var frequencyOptions: [(value: RecurringFrequency, title: String)] {
        RecurringFrequency.allCases.map { ($0, Self.unitTitle($0)) }
    }

    /// "Every 2 weeks".
    public var repeatsTitle: String {
        RecurringDisplay.frequency(frequency, interval: interval)
    }

    public var intervalRange: ClosedRange<Int> {
        RecurringRule.intervalRange
    }

    // MARK: Short subscription form

    public var periodOptions: [(value: SubscriptionPeriod, title: String)] {
        [
            (.monthly, String(localized: "Monthly", bundle: #bundle)),
            (.quarterly, String(localized: "Quarterly", bundle: #bundle)),
            (.halfYearly, String(localized: "Half-yearly", bundle: #bundle)),
            (.yearly, String(localized: "Yearly", bundle: #bundle)),
        ]
    }

    /// The schedule as one of the four periods; monthly while "More options" holds another one.
    public var subscriptionPeriod: SubscriptionPeriod {
        get { SubscriptionPeriod(frequency: frequency, interval: interval) ?? .monthly }
        set {
            frequency = newValue.frequency
            interval = newValue.interval
        }
    }

    /// The first charge from today, before saving: "Tomorrow", "Dec 5".
    public var nextCharge: String? {
        nextDates.first
    }

    /// The short form hides only what already has a value: without a payment method or the
    /// "Subscriptions" category it still asks for them.
    public var shortFormNeedsChoices: Bool {
        method == nil || category == nil
    }

    public func showMoreOptions() {
        showsAllFields = true
    }

    public var showsSubscriptionToggle: Bool {
        kind == .expense
    }

    // MARK: Detail

    /// The next three days it falls on, from today, for the schedule as it is now: they follow the
    /// start, frequency, interval and end while the person edits, also for a rule not saved yet.
    public var nextDates: [String] {
        guard intervalRange.contains(interval) else { return [] }
        let today = now()
        // The end is ignored while it is before the start; saving reports that.
        let end = hasEndDate && calendar.startOfDay(for: endDate) >= calendar.startOfDay(for: startDate) ? endDate : nil
        let candidate = RecurringRule(
            id: ruleID ?? UUID(), name: "", kind: kind, categoryID: nil, amount: 1, currency: currency, accountID: UUID(),
            frequency: frequency, interval: interval, startDate: startDate, endDate: end,
        )
        let keepsSchedule = rule.map {
            $0.startDate == startDate && $0.frequency == frequency && $0.interval == interval
        } ?? false
        let first = rule.flatMap { keepsSchedule ? $0.nextDate : nil }
            ?? RecurringSchedule.rescheduledNextDate(of: candidate, today: today, calendar: calendar)
        return RecurringSchedule.next(3, of: candidate.with(nextDate: first), calendar: calendar).map {
            RecurringDisplay.day($0, today: today, calendar: calendar)
        }
    }

    /// The latest movements it recorded, newest first.
    public var recorded: [Transaction] {
        guard let ruleID, let overview else { return [] }
        return Array(overview.recorded.filter { $0.recurringID == ruleID }.sorted { $0.date > $1.date }.prefix(5))
    }

    public var display: TransactionDisplay? {
        overview.map { TransactionDisplay(accounts: $0.accounts, cards: $0.cards, categories: $0.categories) }
    }

    public func recordedDay(_ transaction: Transaction) -> String {
        RecurringDisplay.day(transaction.date, today: now(), calendar: calendar)
    }
}
