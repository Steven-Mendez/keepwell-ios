import Core
import Domain
import Foundation
import Observation
import RecurringDomain
import SharedPresentation

/// Drives a recurring rule's detail: whether this cycle is paid, when the next payment is, and every
/// movement that paid it. Payments recorded by hand are linked here, or taken out again.
@MainActor
@Observable
public final class RecurringRuleDetailViewModel {
    public enum State: Equatable {
        case loading
        case loaded(RecurringOverview)
        /// Deleted, here or on another device, while its detail was open.
        case missing
        case failed
    }

    public let ruleID: UUID
    public private(set) var state = State.loading
    public private(set) var isWorking = false
    public private(set) var actionError: String?
    /// Narrows "Link a payment" to movements whose description, note or amount contain it.
    public var query = ""

    private let getOverview: any GetRecurringOverviewUseCase
    private let confirmPlanned: (any ConfirmPlannedTransactionUseCase)?
    private let setPaused: (any SetRecurringRulePausedUseCase)?
    private let linkPayment: (any LinkRecurringPaymentUseCase)?
    /// Offers "Undo" after confirming a draft; `nil` in previews.
    private let undo: MovementUndo?
    private let calendar: Calendar
    private let now: () -> Date
    private let formatter = CurrencyFormatter()
    /// Movements offered under "Other movements" before the person searches.
    private static let otherLimit = 30

    public init(
        ruleID: UUID,
        getOverview: any GetRecurringOverviewUseCase,
        confirmPlanned: (any ConfirmPlannedTransactionUseCase)? = nil,
        setPaused: (any SetRecurringRulePausedUseCase)? = nil,
        linkPayment: (any LinkRecurringPaymentUseCase)? = nil,
        undo: MovementUndo? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now },
    ) {
        self.ruleID = ruleID
        self.getOverview = getOverview
        self.confirmPlanned = confirmPlanned
        self.setPaused = setPaused
        self.linkPayment = linkPayment
        self.undo = undo
        self.calendar = calendar
        self.now = now
    }

    public func load() async {
        do {
            let overview = try await getOverview.execute()
            state = overview.rule(ruleID) == nil ? .missing : .loaded(overview)
        } catch {
            state = .failed
        }
    }

    public var overview: RecurringOverview? {
        if case let .loaded(overview) = state {
            overview
        } else {
            nil
        }
    }

    public var rule: RecurringRule? {
        overview?.rule(ruleID)
    }

    public var status: RecurringStatus? {
        guard let overview, let rule else { return nil }
        return RecurringStatus.of(rule, transactions: overview.recorded, today: now(), calendar: calendar)
    }

    public var history: RecurringHistory? {
        guard let overview, let rule else { return nil }
        return RecurringHistory.of(rule, transactions: overview.recorded, today: now(), calendar: calendar)
    }

    public var display: TransactionDisplay? {
        overview.map { TransactionDisplay(accounts: $0.accounts, cards: $0.cards, categories: $0.categories) }
    }

    public var category: TransactionCategory? {
        overview?.categories.first { $0.id == rule?.categoryID }
    }

    // MARK: Header

    /// Signed like a movement: "−$15.99", "+$1,500.00"; transfers carry no sign.
    public var amount: String {
        guard let rule else { return "" }
        let sign: CurrencyFormatter.Sign = rule.kind == .transfer ? .never : .always
        return formatter.string(from: rule.kind == .expense ? -rule.amount : rule.amount, currencyCode: rule.currency, sign: sign)
    }

    /// "Every month · Debit •••• 3922".
    public var schedule: String {
        guard let rule, let overview else { return "" }
        let method: String = if rule.kind == .transfer, let display {
            "\(display.accountName(rule.accountID)) → \(display.accountName(rule.destinationAccountID))"
        } else if let card = overview.cards.first(where: { $0.id == rule.cardID }), card.kind != .transfer {
            CardDisplay.shortName(of: card)
        } else {
            overview.accounts.first { $0.id == rule.accountID }.map(CardDisplay.name(of:)) ?? ""
        }
        return [RecurringDisplay.frequency(of: rule), method].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: Status

    /// "Paid · Nov 1", "Overdue · 3 days", "To confirm", "Upcoming", "Paused" or "Ended".
    public var stateLabel: String {
        guard let status else { return "" }
        switch status.state {
        case .overdue: return String(localized: "Overdue · \(status.daysOverdue) days", bundle: #bundle)
        case .toConfirm: return String(localized: "To confirm", bundle: #bundle)
        case .paused: return String(localized: "Paused", bundle: #bundle)
        case .ended: return String(localized: "Ended", bundle: #bundle)
        case .upcoming: return String(localized: "Upcoming", bundle: #bundle)
        case .paid:
            guard let payment = status.payment else { return String(localized: "Paid", bundle: #bundle) }
            return String(localized: "Paid · \(day(payment.date))", bundle: #bundle)
        }
    }

    /// "Dec 4 · in 18 days", "Tomorrow"; `nil` once the rule ended or while it is paused.
    public var nextPayment: String? {
        guard let status, let next = status.nextDate, rule?.isPaused == false else { return nil }
        let date = day(next)
        let days = status.daysUntilNext ?? 0
        return days >= 2 ? String(localized: "\(date) · in \(days) days", bundle: #bundle) : date
    }

    /// "Last payment Oct 1", when this cycle isn't paid but an earlier one was.
    public var lastPayment: String? {
        guard let status, status.state != .paid, let last = status.lastPayment else { return nil }
        return String(localized: "Last payment \(day(last.date))", bundle: #bundle)
    }

    /// The next three days it falls on; none while paused.
    public var nextDates: [String] {
        guard let rule, !rule.isPaused else { return [] }
        return RecurringSchedule.next(3, of: rule, calendar: calendar).map(day)
    }

    // MARK: Payments

    public var paidThisYear: String {
        history.map { formatter.string($0.paidThisYear) } ?? ""
    }

    public var paymentsCount: String {
        String(localized: "\(history?.paidCount ?? 0) payments", bundle: #bundle)
    }

    /// "Price changed from $5.99 to $6.49", when the latest payment differs from the one before.
    public var priceChange: String? {
        guard let change = history?.priceChange else { return nil }
        return String(localized: "Price changed from \(formatter.string(change.from)) to \(formatter.string(change.to))", bundle: #bundle)
    }

    public func day(_ date: Date) -> String {
        RecurringDisplay.day(date, today: now(), calendar: calendar)
    }

    /// "Nov 1 · Debit •••• 3922", or "Nov 1 · Draft" for an occurrence still waiting.
    public func subtitle(of transaction: Transaction) -> String {
        let method = transaction.isConfirmed
            ? display?.methodName(of: transaction) ?? ""
            : String(localized: "Draft", bundle: #bundle)
        return [day(transaction.date), method].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: Linking

    /// Movements that match the rule's amount or name, latest first.
    public var suggested: [Transaction] {
        guard let overview, let rule else { return [] }
        return RecurringStatus.paymentCandidates(for: rule, in: overview.unlinked).filter(matchesQuery)
    }

    /// Other movements of the rule's kind, latest first: the first few, or the ones the search finds.
    public var others: [Transaction] {
        guard let overview, let rule else { return [] }
        let taken = Set(RecurringStatus.paymentCandidates(for: rule, in: overview.unlinked).map(\.id))
        return Array(
            overview.unlinked
                .filter { !taken.contains($0.id) && RecurringStatus.canLink($0, to: rule) && matchesQuery($0) }
                .sorted { $0.date > $1.date }
                .prefix(Self.otherLimit),
        )
    }

    private func matchesQuery(_ transaction: Transaction) -> Bool {
        let needle = CategorizationRules.folded(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return true }
        let text = "\(transaction.description) \(transaction.note ?? "") \(transaction.amount)"
        return CategorizationRules.folded(text).contains(needle)
    }

    // MARK: Actions

    /// Confirms the rule's waiting draft as Home does: no dialog, "Undo" for a few seconds.
    public func confirm() async {
        guard let confirmPlanned, let planned = status?.draft else { return }
        await perform(String(localized: "We couldn't confirm it. Try again.", bundle: #bundle)) { () async throws(DomainError) in
            try await confirmPlanned.execute(id: planned.id)
        }
        if actionError == nil {
            undo?.offerConfirmed(planned)
        }
    }

    public func togglePaused() async {
        guard let setPaused, let rule else { return }
        await perform(String(localized: "We couldn't save it. Try again.", bundle: #bundle)) { () async throws(DomainError) in
            try await setPaused.execute(id: rule.id, isPaused: !rule.isPaused)
        }
    }

    /// Links a movement as a payment of this rule. Returns whether it did, so the sheet can close.
    public func link(_ transactionID: UUID) async -> Bool {
        guard let linkPayment else { return false }
        await perform(String(localized: "We couldn't link it. Try again.", bundle: #bundle)) { () async throws(DomainError) in
            try await linkPayment.execute(transactionID: transactionID, ruleID: self.ruleID)
        }
        return actionError == nil
    }

    public func unlink(_ transactionID: UUID) async {
        guard let linkPayment else { return }
        await perform(String(localized: "We couldn't save it. Try again.", bundle: #bundle)) { () async throws(DomainError) in
            try await linkPayment.execute(transactionID: transactionID, ruleID: nil)
        }
    }

    private func perform(_ failure: String, _ work: () async throws(DomainError) -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
            actionError = nil
            await load()
        } catch {
            actionError = failure
        }
    }
}
