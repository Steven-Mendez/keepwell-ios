import Domain
import Foundation

public protocol GetRecurringOverviewUseCase: Sendable {
    func execute() async throws(DomainError) -> RecurringOverview
}

public struct DefaultGetRecurringOverviewUseCase: GetRecurringOverviewUseCase {
    private let rules: any RecurringRuleRepository
    private let accounts: any AccountRepository
    private let cards: any CardRepository
    private let categories: any CategoryRepository
    private let transactions: any TransactionRepository
    private let settings: any SettingsRepository
    private let calendar: Calendar

    public init(
        rules: any RecurringRuleRepository,
        accounts: any AccountRepository,
        cards: any CardRepository,
        categories: any CategoryRepository,
        transactions: any TransactionRepository,
        settings: any SettingsRepository,
        calendar: Calendar = .current,
    ) {
        self.calendar = calendar
        self.rules = rules
        self.accounts = accounts
        self.cards = cards
        self.categories = categories
        self.transactions = transactions
        self.settings = settings
    }

    public func execute() async throws(DomainError) -> RecurringOverview {
        let currencies = try await settings.load()?.currencies ?? .initial
        return try await RecurringOverview(
            settings: currencies,
            rules: rules.fetchRecurringRules(),
            accounts: accounts.fetchAccounts(),
            cards: cards.fetchCards(),
            categories: categories.fetchCategories(),
            recorded: transactions.fetchTransactions(in: nil).filter { $0.recurringID != nil },
            calendar: calendar,
        )
    }
}

/// Creates or edits a rule, then records whatever is already due, so a rule that starts today
/// shows its movement right away.
public protocol SaveRecurringRuleUseCase: Sendable {
    @discardableResult
    func execute(_ draft: RecurringRuleDraft) async throws(DomainError) -> RecurringRule
}

public struct DefaultSaveRecurringRuleUseCase: SaveRecurringRuleUseCase {
    private let rules: any RecurringRuleRepository
    private let accounts: any AccountRepository
    private let cards: any CardRepository
    private let categories: any CategoryRepository
    private let settings: any SettingsRepository
    private let materialize: any MaterializeRecurringUseCase
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        rules: any RecurringRuleRepository,
        accounts: any AccountRepository,
        cards: any CardRepository,
        categories: any CategoryRepository,
        settings: any SettingsRepository,
        materialize: any MaterializeRecurringUseCase,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now },
    ) {
        self.rules = rules
        self.accounts = accounts
        self.cards = cards
        self.categories = categories
        self.settings = settings
        self.materialize = materialize
        self.calendar = calendar
        self.now = now
    }

    public func execute(_ draft: RecurringRuleDraft) async throws(DomainError) -> RecurringRule {
        let allCards = try await cards.fetchCards()
        // The account comes from the card when there is one; validation checks the card exists.
        let accountID = draft.cardID.flatMap { id in allCards.first { $0.id == id }?.accountID } ?? draft.accountID
        guard let accountID else { throw .notFound(UUID(uuid: UUID_NULL)) }
        let existing = try await rules.fetchRecurringRules().first { $0.id == draft.id }
        let candidate = RecurringRule(
            id: draft.id,
            name: draft.name,
            kind: draft.kind,
            categoryID: draft.categoryID,
            amount: draft.amount,
            currency: draft.currency,
            accountID: accountID,
            cardID: draft.cardID,
            destinationAccountID: draft.destinationAccountID,
            frequency: draft.frequency,
            interval: draft.interval,
            startDate: draft.startDate,
            endDate: draft.endDate,
            isSubscription: draft.isSubscription,
            autoConfirm: draft.autoConfirm,
            isPaused: existing?.isPaused ?? false,
            note: draft.note,
            // Tags come from "Repeat" on a tagged movement; the rule editor keeps them as they are.
            tags: existing?.tags ?? [],
            // Likewise the merchant and platform "Repeat" copied from the movement; a transfer names
            // neither.
            merchantID: draft.kind == .transfer ? nil : existing?.merchantID,
            viaMerchantID: draft.kind == .transfer ? nil : existing?.viaMerchantID,
        )
        let currencies = try await settings.load()?.currencies ?? .initial
        let valid = try await candidate.validated(
            currencies: currencies,
            accounts: accounts.fetchAccounts(),
            cards: allCards,
            categories: categories.fetchCategories(),
            calendar: calendar,
        )
        let rule = valid.with(nextDate: nextDate(of: valid, existing: existing))
        try await rules.save(rule)
        try await materialize.execute()
        return rule
    }

    /// A new rule, or one whose schedule changed, starts at its first occurrence from today (or
    /// from its start, if later): saving never back-fills the past. Movements already recorded
    /// are left alone, and an edit that keeps the schedule keeps its place.
    private func nextDate(of rule: RecurringRule, existing: RecurringRule?) -> Date {
        if let existing, existing.startDate == rule.startDate, existing.frequency == rule.frequency,
           existing.interval == rule.interval
        {
            return existing.nextDate
        }
        return RecurringSchedule.rescheduledNextDate(of: rule, today: now(), calendar: calendar)
    }
}

/// "Pause" keeps the rule's place; "Resume" starts again from today without recording what was
/// skipped while paused.
public protocol SetRecurringRulePausedUseCase: Sendable {
    func execute(id: UUID, isPaused: Bool) async throws(DomainError)
}

public struct DefaultSetRecurringRulePausedUseCase: SetRecurringRulePausedUseCase {
    private let rules: any RecurringRuleRepository
    private let materialize: any MaterializeRecurringUseCase
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        rules: any RecurringRuleRepository,
        materialize: any MaterializeRecurringUseCase,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now },
    ) {
        self.rules = rules
        self.materialize = materialize
        self.calendar = calendar
        self.now = now
    }

    public func execute(id: UUID, isPaused: Bool) async throws(DomainError) {
        guard let rule = try await rules.fetchRecurringRules().first(where: { $0.id == id }) else { throw .notFound(id) }
        guard rule.isPaused != isPaused else { return }
        if isPaused {
            try await rules.save(rule.with(isPaused: true, nextDate: rule.nextDate))
            return
        }
        let next = RecurringSchedule.firstOccurrence(of: rule, onOrAfter: now(), calendar: calendar) ?? rule.nextDate
        try await rules.save(rule.with(isPaused: false, nextDate: next))
        try await materialize.execute()
    }
}
