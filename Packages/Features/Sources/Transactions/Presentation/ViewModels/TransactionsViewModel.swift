import Core
import Domain
import Foundation
import Observation
import SharedPresentation
import TransactionsDomain

enum MovementTone { case neutral, positive, negative }

@MainActor
@Observable
public final class TransactionsViewModel {
    public enum State: Equatable {
        case loading
        case loaded(TransactionList)
        case failed
    }

    public struct Section: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let transactions: [Transaction]
    }

    public private(set) var state = State.loading
    public var filter = TransactionFilter.all
    /// The account or card the list is narrowed to; `.all` shows every movement.
    public var scope = TransactionScope.all
    public var query = ""
    /// Bounds on the amount in the principal currency; empty shows every amount.
    public var amount = AmountRange()
    /// Where the movements came from: any, subscriptions, or one recurring rule ("See all" on it).
    public var origin = TransactionOrigin.any
    /// Set by whoever opens the list to search ("Search transactions" on home); the view focuses
    /// the field and clears it.
    public var wantsSearchFocus = false
    public private(set) var actionError: String?

    private let getList: any GetTransactionListUseCase
    private let confirmPlanned: any ConfirmPlannedTransactionUseCase
    private let deleteTransaction: any DeleteTransactionUseCase
    private let filterTransactions: any FilterTransactionsUseCase
    /// Offers "Undo" after a delete or a confirm; `nil` in previews.
    private let undo: MovementUndo?
    private let calendar: Calendar
    private let now: () -> Date
    let formatter = CurrencyFormatter()

    public init(
        getList: any GetTransactionListUseCase,
        confirmPlanned: any ConfirmPlannedTransactionUseCase,
        deleteTransaction: any DeleteTransactionUseCase,
        filterTransactions: any FilterTransactionsUseCase = DefaultFilterTransactionsUseCase(),
        undo: MovementUndo? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now },
    ) {
        self.undo = undo
        self.getList = getList
        self.confirmPlanned = confirmPlanned
        self.deleteTransaction = deleteTransaction
        self.filterTransactions = filterTransactions
        self.calendar = calendar
        self.now = now
    }

    public var list: TransactionList? {
        if case let .loaded(list) = state {
            list
        } else {
            nil
        }
    }

    public func load() async {
        do {
            state = try await .loaded(getList.execute())
        } catch {
            state = .failed
        }
    }

    public func confirm(_ id: UUID) async {
        let planned = list?.transactions.first { $0.id == id }
        await perform { () async throws(DomainError) in try await confirmPlanned.execute(id: id) }
        if actionError == nil, let planned {
            undo?.offerConfirmed(planned)
        }
    }

    public func delete(_ id: UUID) async {
        let deleted = list?.transactions.first { $0.id == id }
        await perform { () async throws(DomainError) in try await deleteTransaction.execute(id: id) }
        if actionError == nil, let deleted {
            undo?.offerDeleted(deleted)
        }
    }

    private func perform(_ action: () async throws(DomainError) -> Void) async {
        do {
            try await action()
            actionError = nil
            await load()
        } catch {
            actionError = String(localized: "We couldn't save the change. Try again.", bundle: #bundle)
        }
    }

    // MARK: - Display

    var display: TransactionDisplay? {
        list.map { TransactionDisplay(accounts: $0.accounts, cards: $0.cards, categories: $0.categories) }
    }

    public var hasTransactions: Bool {
        list?.transactions.isEmpty == false
    }

    private var transactionQuery: TransactionQuery {
        TransactionQuery(kind: filter, scope: scope, text: query, amount: amount, origin: origin)
    }

    /// What the chips, the account filter and the search leave visible, newest first.
    func visibleTransactions(ignoringKind: Bool = false) -> [Transaction] {
        guard let list, let display else { return [] }
        var query = transactionQuery
        if ignoringKind {
            query.kind = .all
        }
        // Tags are searchable as text too: "boda" finds "#boda" among everything else it matches.
        return filterTransactions.execute(list.transactions, matching: query, context: queryContext) { transaction in
            ([display.searchableText(of: transaction)] + transaction.tags.map(TagDisplay.label)).joined(separator: " ")
        }
    }

    /// The subtitle under a movement: its usual line, then its tags ("#boda #viaje").
    func subtitle(of transaction: Transaction, display: TransactionDisplay) -> String {
        [display.subtitle(of: transaction), TagDisplay.line(transaction.tags)].compactMap(\.self).joined(separator: " · ")
    }

    /// Narrows the list to a tag, as typing "#boda" in the search does.
    public func show(tag: String) {
        query = TagDisplay.label(tag)
    }

    /// Every movement with a tag, whatever the list was narrowed to before (a tag tapped in a
    /// movement's detail).
    public func showOnly(tag: String) {
        filter = .all
        scope = .all
        amount = AmountRange()
        origin = .any
        show(tag: tag)
    }

    /// "#boda · All time", "−$1,240.00" and "+$300.00" while the search is a tag: what that tag
    /// came to in the chosen account, in the principal currency, never mixed. Replaces the month's
    /// totals, since a trip or a wedding rarely fits in one month.
    var tagTotals: (title: String, spent: String, earned: String)? {
        guard let list, let tag = transactionQuery.tag else { return nil }
        let totals = TagTotals(tag: tag, transactions: visibleTransactions(ignoringKind: true), currency: list.settings.principal)
        let label = TagDisplay.label(tag)
        let title = String(localized: "\(label) · All time", bundle: #bundle)
        let spent = formatter.string(from: -totals.expense, currencyCode: totals.currency)
        let earned = formatter.string(from: totals.income, currencyCode: totals.currency, sign: .always)
        return (title, spent, earned)
    }

    /// Planned movements first, then confirmed ones grouped by day, newest first.
    public var sections: [Section] {
        let visible = visibleTransactions()
        var sections: [Section] = []
        let planned = visible.filter { !$0.isConfirmed }.sorted { $0.date < $1.date }
        if !planned.isEmpty {
            sections.append(Section(
                id: "planned",
                title: String(localized: "Drafts · they don't affect balances", bundle: #bundle),
                transactions: planned,
            ))
        }
        var current: (day: Date, items: [Transaction])?
        for transaction in visible where transaction.isConfirmed {
            let day = calendar.startOfDay(for: transaction.date)
            if current?.day == day {
                current?.items.append(transaction)
            } else {
                if let current {
                    sections.append(daySection(current.day, current.items))
                }
                current = (day, [transaction])
            }
        }
        if let current {
            sections.append(daySection(current.day, current.items))
        }
        return sections
    }

    private func daySection(_ day: Date, _ items: [Transaction]) -> Section {
        Section(id: day.ISO8601Format(), title: dayTitle(day), transactions: items)
    }

    /// "22 October", with the year only when it isn't this year's.
    func dayTitle(_ day: Date) -> String {
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now())
        return sameYear
            ? day.formatted(.dateTime.day().month(.wide))
            : day.formatted(.dateTime.day().month(.wide).year())
    }

    /// "October 2026", "−$709.58" and "+$2,452.24" for the current month's confirmed movements of
    /// the chosen account and search, apart so the view can color what went out and what came in.
    /// The kind chips don't change it: they pick which rows to read within the same month. Amounts
    /// are converted to the principal currency, never mixed.
    var monthTotals: (title: String, spent: String, earned: String)? {
        if let tagTotals {
            return tagTotals
        }
        guard let summary = monthSummary else { return nil }
        let title = now().formatted(.dateTime.month(.wide).year()).sentenceCased
        let spent = formatter.string(from: -summary.expense, currencyCode: summary.currency)
        let earned = formatter.string(from: summary.income, currencyCode: summary.currency, sign: .always)
        return (title, spent, earned)
    }

    /// "Not including 3 movements in USD", one line per currency the month's totals leave out
    /// because their stored rate doesn't reach the principal currency (recorded before it changed).
    /// Counts, not amounts, so they show even with amounts hidden. Empty with a tag search.
    var excludedMovementLines: [String] {
        guard tagTotals == nil, let summary = monthSummary else { return [] }
        return summary.excluded.map { excluded in
            String(localized: "Not including \(excluded.count) movements in \(excluded.currency)", bundle: #bundle)
        }
    }

    private var monthSummary: MonthlySummary? {
        guard let list else { return nil }
        return MonthlySummary(
            month: YearMonth(containing: now(), calendar: calendar),
            transactions: visibleTransactions(ignoringKind: true),
            currency: list.settings.principal,
            calendar: calendar,
        )
    }

    /// "Movements", "Money in", "Money out" and "Net" for what the chips, the account and the search
    /// leave visible, in the principal currency. `nil` until the list loads.
    var movementTotals: [(title: String, value: String, tone: MovementTone)]? {
        guard let list else { return nil }
        let totals = MovementTotals(of: visibleTransactions(), currency: list.settings.principal)
        return [
            (String(localized: "Movements", bundle: #bundle), String(totals.count), .neutral),
            (
                String(localized: "Money in", bundle: #bundle),
                formatter.string(from: totals.moneyIn, currencyCode: totals.currency),
                .positive,
            ),
            (
                String(localized: "Money out", bundle: #bundle),
                formatter.string(from: totals.moneyOut, currencyCode: totals.currency),
                .negative,
            ),
            (
                String(localized: "Net", bundle: #bundle),
                formatter.string(from: totals.net, currencyCode: totals.currency, sign: .always),
                .neutral,
            ),
        ]
    }

    // MARK: - Account filter

    public var scopeOptions: [TransactionScopeOption] {
        list?.scopeOptions ?? []
    }

    /// The account filter chip: "All accounts" or "Bank One Savings".
    var scopeTitle: String {
        list?.account(in: scope).map(CardDisplay.name(of:)) ?? String(localized: "All accounts", bundle: #bundle)
    }

    /// The balance behind the chosen account or card, LAFISE-style: "Available balance" for money
    /// the person holds, "Current debt" (as an amount owed) for a credit card, as the card's own
    /// screen shows it. A single-currency account shows its own currency (cash in córdobas stays
    /// in córdobas); one in two currencies headlines the principal-currency total and
    /// lists each currency under it. `nil` without an account filter.
    var scopeBalance: (label: String, amount: String, details: [String])? {
        guard let list, let account = list.account(in: scope),
              let balances = list.balances(in: scope, calendar: calendar),
              let total = list.balanceTotal(in: scope, calendar: calendar) else { return nil }
        let isCredit = account.kind == .credit
        let shown: (Money) -> String = { money in
            self.formatter.string(isCredit ? Money(-money.amount, money.currency) : money)
        }
        let label = isCredit
            ? String(localized: "Current debt", bundle: #bundle)
            : String(localized: "Available balance", bundle: #bundle)
        guard balances.count > 1 else { return (label, balances.first.map(shown) ?? shown(total), []) }
        return (label, shown(total), (isCredit ? balances.reversed() : balances).map(shown))
    }

    /// Shown when an account has nothing yet, so it doesn't read as a search that failed.
    var isScopeEmpty: Bool {
        scope != .all && query.trimmingCharacters(in: .whitespaces).isEmpty && filter == .all
            && amount.isEmpty && origin == .any && visibleTransactions().isEmpty
    }

    func filterTitle(_ filter: TransactionFilter) -> String {
        switch filter {
        case .all: String(localized: "All", bundle: #bundle)
        case .expense: String(localized: "Expenses", bundle: #bundle)
        case .income: String(localized: "Income", bundle: #bundle)
        case .transfer: String(localized: "Transfers", bundle: #bundle)
        case .planned: String(localized: "Drafts", bundle: #bundle)
        }
    }
}
