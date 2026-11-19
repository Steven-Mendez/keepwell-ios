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

    public private(set) var state = State.loading {
        didSet {
            pendingDrafts = Self.pendingDrafts(in: overview, now: now(), calendar: calendar)
            statuses = Self.statuses(in: overview, now: now(), calendar: calendar)
        }
    }

    /// Where each rule stands (paid, a draft waiting, its next date), by rule: once per load.
    private var statuses: [UUID: RecurringStatus] = [:]

    /// The draft each rule left waiting from today or before, by rule: derived once per load from
    /// the same list home reads (`UpcomingPayments`), not per row.
    private var pendingDrafts: [UUID: PendingRuleDraft] = [:]
    /// Drafts being confirmed from their rule's row, so the button can't fire twice.
    public private(set) var confirming: Set<UUID> = []
    public private(set) var actionError: String?

    private let getOverview: any GetRecurringOverviewUseCase
    private let confirmPlanned: (any ConfirmPlannedTransactionUseCase)?
    /// Offers "Undo" after confirming a draft; `nil` in previews.
    private let undo: MovementUndo?
    private let calendar: Calendar
    private let now: () -> Date
    let formatter = CurrencyFormatter()
    static let maskedAmount = "••••"

    public init(
        getOverview: any GetRecurringOverviewUseCase,
        confirmPlanned: (any ConfirmPlannedTransactionUseCase)? = nil,
        undo: MovementUndo? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now },
    ) {
        self.getOverview = getOverview
        self.confirmPlanned = confirmPlanned
        self.undo = undo
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

    /// "Not including 2 subscriptions in EUR", one line per currency the total can't convert. Counts,
    /// not amounts, so they show even with amounts hidden.
    public var excludedSubscriptions: [String] {
        guard let overview else { return [] }
        return overview.excludedSubscriptions.map { excluded in
            String(localized: "Not including \(excluded.count) subscriptions in \(excluded.currency)", bundle: #bundle)
        }
    }

    // MARK: Rows

    public func category(of rule: RecurringRule) -> TransactionCategory? {
        overview?.categories.first { $0.id == rule.categoryID }
    }

    /// The rule's own merchant's logo first, then the brand its name names.
    public func logo(of rule: RecurringRule) -> LogoSubject? {
        MerchantLogos.logo(of: rule, merchants: overview?.merchants ?? [])
    }

    /// "Every month · Tomorrow · Debit •••• 3922", or "Paused" in place of the date. While a draft
    /// waits (`pendingDraft(of:)`), the date gives way to its state, which the row shows apart;
    /// once paid, the row says so apart too and the date reads "Next Dec 1".
    public func subtitle(of rule: RecurringRule) -> String {
        // A rule an assistant proposed waits paused until the person resumes (confirms) or deletes it.
        let when = rule.source == .mcp && rule.isPaused
            ? String(localized: "Proposed by Claude · resume to confirm", bundle: #bundle)
            : pendingDraft(of: rule) != nil ? ""
            : rule.isPaused ? String(localized: "Paused", bundle: #bundle)
            : paidLabel(of: rule) != nil ? String(localized: "Next \(nextLabel(of: rule))", bundle: #bundle)
            : nextLabel(of: rule)
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

    /// "Paid · Nov 1" while the cycle that ends at the rule's next date has a confirmed payment.
    public func paidLabel(of rule: RecurringRule) -> String? {
        guard let status = statuses[rule.id], status.state == .paid, let payment = status.payment else { return nil }
        return String(localized: "Paid · \(shortDay(payment.date))", bundle: #bundle)
    }

    /// "3 of 8 paid this month · $41.97 left to pay": the expense rules due this month. `nil` when
    /// none is. Each currency's remainder stands alone, never summed with another's.
    public func monthProgress(hidden: Bool) -> String? {
        guard let overview else { return nil }
        let progress = RecurringMonthProgress.of(overview.rules, transactions: overview.recorded, today: now(), calendar: calendar)
        guard progress.total > 0 else { return nil }
        let paid = String(localized: "\(progress.paid) of \(progress.total) paid this month", bundle: #bundle)
        guard !progress.remaining.isEmpty else { return paid }
        let amounts = hidden ? Self.maskedAmount : progress.remaining.map { formatter.string($0) }.joined(separator: " + ")
        return paid + " · " + String(localized: "\(amounts) left to pay", bundle: #bundle)
    }

    private static func statuses(in overview: RecurringOverview?, now: Date, calendar: Calendar) -> [UUID: RecurringStatus] {
        guard let overview else { return [:] }
        return Dictionary(uniqueKeysWithValues: overview.rules.map { rule in
            (rule.id, RecurringStatus.of(rule, transactions: overview.recorded, today: now, calendar: calendar))
        })
    }

    /// "Nov 12", with the year when it isn't this one.
    private func shortDay(_ date: Date) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now())
        var style: Date.FormatStyle = sameYear ? .dateTime.day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year()
        style.timeZone = calendar.timeZone
        // Spanish abbreviates months with a trailing dot ("nov."), which reads badly mid-sentence.
        return date.formatted(style).replacingOccurrences(of: ".", with: "")
    }

    /// The draft the rule left waiting from today or before, if any.
    public func pendingDraft(of rule: RecurringRule) -> PendingRuleDraft? {
        pendingDrafts[rule.id]
    }

    private static func pendingDrafts(in overview: RecurringOverview?, now: Date, calendar: Calendar) -> [UUID: PendingRuleDraft] {
        guard let overview else { return [:] }
        let ledger = UpcomingPayments.Ledger(transactions: overview.recorded, settings: overview.settings)
        let payments = UpcomingPayments.compute(ledger, on: now, days: 0, calendar: calendar)
        return UpcomingPayments.pendingRuleDrafts(payments)
    }

    /// "To confirm · Nov 12" for today's draft, "Overdue · 3 days" for an older one.
    public func pendingLabel(_ pending: PendingRuleDraft) -> String {
        if pending.daysOverdue > 0 {
            return String(localized: "Overdue · \(pending.daysOverdue) days", bundle: #bundle)
        }
        let day = shortDay(pending.transaction.date)
        return String(localized: "To confirm · \(day)", bundle: #bundle)
    }

    /// Confirms the rule's waiting draft as Home does: no dialog, "Undo" for a few seconds.
    public func confirm(_ pending: PendingRuleDraft) async {
        let planned = pending.transaction
        guard let confirmPlanned, !confirming.contains(planned.id) else { return }
        confirming.insert(planned.id)
        defer { confirming.remove(planned.id) }
        do {
            try await confirmPlanned.execute(id: planned.id)
            actionError = nil
            undo?.offerConfirmed(planned)
            await load()
        } catch {
            actionError = String(localized: "We couldn't confirm it. Try again.", bundle: #bundle)
        }
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
