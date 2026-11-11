import Core
import Domain
import Foundation
import HomeDomain
import Observation
import RecurringDomain
import SharedPresentation

@MainActor
@Observable
public final class HomeViewModel {
    public enum State: Equatable {
        case loading
        case loaded(HomeOverview)
        case failed
    }

    public private(set) var state = State.loading
    /// Planned movements being confirmed, so their button can't be tapped twice.
    public private(set) var confirming: Set<UUID> = []
    public private(set) var actionError: String?
    /// The name given in onboarding or Settings, read on every load so a change there shows here.
    public private(set) var preferredName: String?

    private let getOverview: any GetHomeOverviewUseCase
    private let confirmPlanned: any ConfirmPlannedTransactionUseCase
    /// Throws away a draft an assistant recorded; `nil` where nothing can be discarded (previews).
    private let discard: (any DeleteTransactionUseCase)?
    private let getPreferredName: any GetPreferredNameUseCase
    /// Confirming (resuming) or discarding (deleting) a rule an assistant proposed; `nil` in previews.
    private let resumeRule: (any SetRecurringRulePausedUseCase)?
    private let deleteRule: (any DeleteRecurringRuleUseCase)?
    let calendar: Calendar
    let formatter = CurrencyFormatter()

    public init(
        getOverview: any GetHomeOverviewUseCase,
        confirmPlanned: any ConfirmPlannedTransactionUseCase,
        getPreferredName: any GetPreferredNameUseCase,
        discard: (any DeleteTransactionUseCase)? = nil,
        resumeRule: (any SetRecurringRulePausedUseCase)? = nil,
        deleteRule: (any DeleteRecurringRuleUseCase)? = nil,
        calendar: Calendar = .current,
    ) {
        self.getOverview = getOverview
        self.confirmPlanned = confirmPlanned
        self.discard = discard
        self.resumeRule = resumeRule
        self.deleteRule = deleteRule
        self.getPreferredName = getPreferredName
        self.calendar = calendar
    }

    public var overview: HomeOverview? {
        if case let .loaded(overview) = state {
            overview
        } else {
            nil
        }
    }

    public func load() async {
        preferredName = await getPreferredName.execute()
        do {
            state = try await .loaded(getOverview.execute())
        } catch {
            state = .failed
        }
    }

    public func confirm(_ id: UUID) async {
        guard !confirming.contains(id) else { return }
        confirming.insert(id)
        defer { confirming.remove(id) }
        do {
            try await confirmPlanned.execute(id: id)
            actionError = nil
            await load()
        } catch {
            actionError = String(localized: "We couldn't confirm it. Try again.", bundle: #bundle)
        }
    }

    /// Discards an assistant's draft: it never happened, so it is deleted rather than confirmed.
    public func discardDraft(_ transaction: Transaction) async {
        guard let discard, transaction.source == .mcp, !transaction.isConfirmed else { return }
        do {
            try await discard.execute(id: transaction.id)
            actionError = nil
            await load()
        } catch {
            actionError = String(localized: "We couldn't confirm it. Try again.", bundle: #bundle)
        }
    }

    public var canResolveProposals: Bool {
        resumeRule != nil && deleteRule != nil
    }

    /// Confirms a proposed rule: it starts from today, as when resumed from Recurring.
    public func confirmProposal(_ rule: RecurringRule) async {
        guard let resumeRule else { return }
        await resolve { () async throws(DomainError) in try await resumeRule.execute(id: rule.id, isPaused: false) }
    }

    /// Discards a proposed rule, which never started, by deleting it.
    public func discardProposal(_ rule: RecurringRule) async {
        guard let deleteRule else { return }
        await resolve { () async throws(DomainError) in try await deleteRule.execute(id: rule.id) }
    }

    private func resolve(_ work: () async throws(DomainError) -> Void) async {
        do {
            try await work()
            actionError = nil
            await load()
        } catch {
            actionError = String(localized: "We couldn't save the change. Try again.", bundle: #bundle)
        }
    }

    /// "10 USD · Monthly", as the web lists a proposal.
    func proposalSubtitle(_ rule: RecurringRule, hidden: Bool) -> String {
        let amount = hidden ? Self.maskedAmount : formatter.string(from: rule.amount, currencyCode: rule.currency)
        return amount + " · " + RecurringDisplay.frequency(of: rule)
    }

    public var canDiscardDrafts: Bool {
        discard != nil
    }

    // MARK: - Display

    var display: TransactionDisplay? {
        overview.map { TransactionDisplay(accounts: $0.accounts, cards: $0.cards, categories: $0.categories) }
    }

    /// "≈ C$408,634 · rate 36.6243".
    func secondCurrencyLine(_ overview: HomeOverview) -> String? {
        guard let second = overview.netWorthInSecond else { return nil }
        let amount = formatter.string(second, fractionDigits: 0)
        let rate = formatter.number(overview.settings.rate, fractionDigits: 4)
        return String(localized: "≈ \(amount) · rate \(rate)", bundle: #bundle)
    }

    func countsLine(_ overview: HomeOverview) -> String {
        // Two strings so each number gets its own plural form.
        let accounts = overview.accountCount
        let cards = overview.cardCount
        return String(localized: "\(accounts) accounts", bundle: #bundle) + " · " + String(localized: "\(cards) cards", bundle: #bundle)
    }

    /// The month's name as the person's locale writes it standing alone ("October").
    func monthName(_ month: YearMonth) -> String {
        guard let start = month.dateInterval(in: calendar)?.start else { return month.description }
        return start.formatted(.dateTime.month(.wide))
    }

    func spentTitle(_ overview: HomeOverview) -> String {
        let month = monthName(overview.month.month)
        return String(localized: "Spent in \(month)", bundle: #bundle)
    }

    func savedBadge(_ overview: HomeOverview) -> String? {
        guard let rate = overview.month.savingsRate, rate > 0 else { return nil }
        let percent = formatter.number(rate * 100, fractionDigits: 0)
        return String(localized: "\(percent)% saved", bundle: #bundle)
    }

    func money(_ amount: Decimal, _ overview: HomeOverview) -> String {
        formatter.string(from: amount, currencyCode: overview.settings.principal)
    }

    /// "They don't count toward balances until you confirm them · C$7,500 (≈ $204.78)".
    func plannedCaption(_ overview: HomeOverview, hidden: Bool = false) -> String {
        let summary = overview.plannedSummary
        guard !hidden else {
            return String(localized: "They don't count toward balances until you confirm them · \(Self.maskedAmount)", bundle: #bundle)
        }
        let principal = formatter.string(from: summary.principalTotal, currencyCode: overview.settings.principal)
        let total = if let second = overview.settings.second {
            "\(formatter.string(from: summary.secondTotal, currencyCode: second, fractionDigits: 0)) (≈ \(principal))"
        } else {
            principal
        }
        return String(localized: "They don't count toward balances until you confirm them · \(total)", bundle: #bundle)
    }

    /// The next three recurring occurrences within a week, for the "Upcoming" card.
    func upcomingPreview(_ overview: HomeOverview, now: Date = .now) -> [RecurringOccurrence] {
        let limit = calendar.date(byAdding: .day, value: Self.upcomingDays, to: calendar.startOfDay(for: now)) ?? now
        return Array(overview.upcoming.filter { calendar.startOfDay(for: $0.date) <= limit }.prefix(Self.upcomingCount))
    }

    /// "Tomorrow · Mastercard ··4321".
    func upcomingSubtitle(_ occurrence: RecurringOccurrence, now: Date = .now) -> String {
        let day = RecurringDisplay.day(occurrence.date, today: now, calendar: calendar)
        let movement = RecurringSchedule.movement(
            from: occurrence.rule,
            on: occurrence.date,
            exchangeRate: .single(occurrence.rule.currency),
        )
        let method = display.map { $0.subtitle(of: movement) } ?? ""
        return [day, method].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    func upcomingAmount(_ occurrence: RecurringOccurrence, hidden: Bool) -> String {
        let movement = RecurringSchedule.movement(
            from: occurrence.rule,
            on: occurrence.date,
            exchangeRate: .single(occurrence.rule.currency),
        )
        return visible(display?.amount(of: movement) ?? "", hidden: hidden)
    }

    static let upcomingDays = 7
    static let upcomingCount = 3

    func plannedTitle(_ overview: HomeOverview) -> String {
        let count = overview.plannedSummary.count
        return String(localized: "Drafts · \(count)", bundle: #bundle)
    }
}
