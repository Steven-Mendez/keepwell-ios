import Foundation

/// One thing pending in the next days: a draft to confirm, an occurrence a rule hasn't recorded
/// yet, a card payment or a loan installment. Home, its status line, the Recurring rows and the
/// web and MCP read the same list, so none of them contradicts another. Port of the web's
/// `upcomingPayments` (`domain/upcoming-payments.ts`); the shared cases are in `upcoming.json`.
public struct UpcomingPayment: Hashable, Sendable, Identifiable {
    /// Overdue: its day is before today. Today: it's today's. Upcoming: a later day in the window.
    public enum Status: String, Hashable, Sendable {
        case overdue
        case today
        case upcoming
    }

    public enum Kind: Hashable, Sendable {
        /// A movement waiting to be confirmed, from a rule or not. Id `draft:<transactionId>`.
        case draft(Transaction)
        /// An occurrence a rule hasn't recorded yet. Id `recurring:<ruleId>:<yyyy-mm-dd>`.
        case recurring(RecurringRule)
        /// A credit card's next payment, in the principal currency. Id `card:<accountId>:<yyyy-mm-dd>`.
        case card(accountID: UUID, dueDay: Int)
        /// An unpaid loan installment, in the loan's currency. Id `installment:<loanId>:<number>`.
        case installment(loanID: UUID, number: Int, count: Int)
        /// A personal debt with a due date, what's left of it. Id `debt:<debtId>`. Produced once
        /// personal debts have a due date (T24); every reader already handles it.
        case debt(debtID: UUID, person: String, direction: DebtDirection)

        /// Within one day: what needs the person first (drafts, installments, cards), then the rest.
        var rank: Int {
            switch self {
            case .draft: 0
            case .installment: 1
            case .card: 2
            case .recurring: 3
            case .debt: 4
            }
        }
    }

    /// Stable and the same on every platform (ids lowercased, as the web prints them).
    public let id: String
    public let kind: Kind
    public let date: Date
    public let amount: Money
    public let status: Status
    /// Calendar days from today to its day: negative when overdue.
    public let daysFromToday: Int

    public init(id: String, kind: Kind, date: Date, amount: Money, daysFromToday: Int) {
        self.id = id
        self.kind = kind
        self.date = date
        self.amount = amount
        self.daysFromToday = daysFromToday
        status = daysFromToday < 0 ? .overdue : daysFromToday == 0 ? .today : .upcoming
    }

    /// By day, then kind, then id in byte order (never a locale comparison, which changes between
    /// platforms).
    public static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.daysFromToday != rhs.daysFromToday {
            return lhs.daysFromToday < rhs.daysFromToday
        }
        if lhs.kind.rank != rhs.kind.rank {
            return lhs.kind.rank < rhs.kind.rank
        }
        return Array(lhs.id.utf8).lexicographicallyPrecedes(Array(rhs.id.utf8))
    }
}

public enum UpcomingPayments {
    /// What the list is read from.
    public struct Ledger: Sendable {
        public var transactions: [Transaction]
        public var rules: [RecurringRule]
        public var accounts: [Account]
        public var loans: [Loan]
        public var settings: CurrencySettings

        public init(
            transactions: [Transaction] = [],
            rules: [RecurringRule] = [],
            accounts: [Account] = [],
            loans: [Loan] = [],
            settings: CurrencySettings = .initial,
        ) {
            self.transactions = transactions
            self.rules = rules
            self.accounts = accounts
            self.loans = loans
            self.settings = settings
        }
    }

    /// Today and the last day in the calendar's zone, and how to read a date against them.
    private struct Window {
        let now: Date
        let days: Int
        let today: Date
        let last: Date
        let calendar: Calendar

        func contains(_ date: Date) -> Bool {
            calendar.startOfDay(for: date) <= last
        }

        func payment(_ id: String, _ kind: UpcomingPayment.Kind, on date: Date, amount: Money) -> UpcomingPayment {
            let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
            return UpcomingPayment(id: id, kind: kind, date: date, amount: amount, daysFromToday: days)
        }

        /// `yyyy-mm-dd` in the calendar's zone, like the web's `dayKey`.
        func key(_ date: Date) -> String {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }
    }

    /// Everything pending from any past day through `days` calendar days after today, overdue first
    /// from the oldest, then by day (`UpcomingPayment.precedes`).
    ///
    /// - drafts dated up to the last day, however old: overdue before today;
    /// - occurrences rules haven't recorded yet (`RecurringSchedule.upcoming`), never overdue; paused
    ///   and ended rules have none. Income and transfers too: the reader filters by kind;
    /// - card payments due by the last day, only when `CardStatement.amountDue` asks for something,
    ///   never overdue (without a payment linked to the statement a late one can't be told apart);
    /// - unpaid loan installments due by the last day, the past ones too.
    ///
    /// Amounts stay in their own currency; a card's is in the principal currency.
    public static func compute(_ ledger: Ledger, on now: Date, days: Int, calendar: Calendar) -> [UpcomingPayment] {
        let today = calendar.startOfDay(for: now)
        guard let last = calendar.date(byAdding: .day, value: days, to: today) else { return [] }
        let window = Window(now: now, days: days, today: today, last: last, calendar: calendar)
        let found = drafts(ledger, window) + recurring(ledger, window) + cards(ledger, window) + installments(ledger, window)
        return found.sorted(by: UpcomingPayment.precedes)
    }

    private static func drafts(_ ledger: Ledger, _ window: Window) -> [UpcomingPayment] {
        ledger.transactions.filter { !$0.isConfirmed && window.contains($0.date) }.map { transaction in
            window.payment(
                "draft:\(transaction.id.lowercased)",
                .draft(transaction),
                on: transaction.date,
                amount: Money(transaction.amount, transaction.currency),
            )
        }
    }

    private static func recurring(_ ledger: Ledger, _ window: Window) -> [UpcomingPayment] {
        RecurringSchedule.upcoming(ledger.rules, from: window.now, days: window.days, calendar: window.calendar).map { occurrence in
            let rule = occurrence.rule
            return window.payment(
                "recurring:\(rule.id.lowercased):\(window.key(occurrence.date))",
                .recurring(rule),
                on: occurrence.date,
                amount: Money(rule.amount, rule.currency),
            )
        }
    }

    private static func cards(_ ledger: Ledger, _ window: Window) -> [UpcomingPayment] {
        ledger.accounts.filter { $0.kind == .credit }.compactMap { account in
            guard let dueDay = account.creditTerms?.dueDay,
                  let due = BillingCycle.nextOccurrence(ofDay: dueDay, onOrAfter: window.now, calendar: window.calendar),
                  window.contains(due)
            else { return nil }
            let owed = CardStatement.amountDue(
                on: due,
                account: account,
                transactions: ledger.transactions,
                settings: ledger.settings,
                calendar: window.calendar,
            )
            // Nothing to pay is nothing pending; the payment reminder still says the day has come.
            guard owed > 0 else { return nil }
            return window.payment(
                "card:\(account.id.lowercased):\(window.key(due))",
                .card(accountID: account.id, dueDay: dueDay),
                on: due,
                amount: Money(owed, ledger.settings.principal),
            )
        }
    }

    private static func installments(_ ledger: Ledger, _ window: Window) -> [UpcomingPayment] {
        ledger.loans.flatMap { loan in
            LoanProgress(loan: loan, today: window.now, calendar: window.calendar).installments
                .filter { !$0.isPaid && $0.number <= loan.installmentCount && window.contains($0.dueDate) }
                .map { installment in
                    window.payment(
                        "installment:\(loan.id.lowercased):\(installment.number)",
                        .installment(loanID: loan.id, number: installment.number, count: loan.installmentCount),
                        on: installment.dueDate,
                        amount: Money(loan.installmentAmount, loan.borrowed.currency),
                    )
                }
        }
    }

    /// The draft each rule left waiting to be confirmed, by rule id: of its drafts dated today or
    /// earlier, the oldest, since that's the one most overdue. The Recurring row shows it in place
    /// of the next date. Pass `compute(…, days: 0, …)`.
    public static func pendingRuleDrafts(_ payments: [UpcomingPayment]) -> [UUID: PendingRuleDraft] {
        var pending: [UUID: PendingRuleDraft] = [:]
        for payment in payments where payment.status != .upcoming {
            guard case let .draft(transaction) = payment.kind, let ruleID = transaction.recurringID else { continue }
            if let current = pending[ruleID]?.transaction,
               (current.date, current.id.lowercased) <= (transaction.date, transaction.id.lowercased)
            {
                continue
            }
            pending[ruleID] = PendingRuleDraft(transaction: transaction, daysOverdue: max(0, -payment.daysFromToday))
        }
        return pending
    }
}

/// A draft a recurring rule left waiting to be confirmed, dated today or before.
public struct PendingRuleDraft: Hashable, Sendable {
    public let transaction: Transaction
    /// Calendar days from its date to today: 0 when it's today's.
    public let daysOverdue: Int

    public init(transaction: Transaction, daysOverdue: Int) {
        self.transaction = transaction
        self.daysOverdue = daysOverdue
    }
}

extension UUID {
    fileprivate var lowercased: String {
        uuidString.lowercased()
    }
}
