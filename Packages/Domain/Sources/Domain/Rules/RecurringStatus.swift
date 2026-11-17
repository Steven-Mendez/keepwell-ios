import Foundation

/// Whether a recurring rule is paid, what it has been paid with and when it's next due: what the
/// Recurring rows and the rule's detail read. Port of the web's `domain/recurring-status.ts`, which
/// the MCP reads too, so the three say the same.
public struct RecurringStatus: Hashable, Sendable {
    public enum State: String, Hashable, Sendable {
        /// A draft the rule left waits from before today.
        case overdue
        /// A draft the rule left waits from today.
        case toConfirm
        case paused
        case ended
        /// The cycle that ends at its next date has a confirmed payment.
        case paid
        /// Nothing to do until its next date.
        case upcoming
    }

    public let state: State
    /// The next occurrence the rule will record; none once it ended.
    public let nextDate: Date?
    /// Calendar days from today to `nextDate`: 0 today, negative when it's behind.
    public let daysUntilNext: Int?
    /// The oldest draft of the rule dated today or before, for `overdue` and `toConfirm`.
    public let draft: Transaction?
    /// Calendar days from the draft's day to today.
    public let daysOverdue: Int
    /// The confirmed payment of the current cycle, when there is one.
    public let payment: Transaction?
    /// The latest confirmed payment linked to the rule, in any cycle.
    public let lastPayment: Transaction?
    /// The occurrence the current cycle pays: the one before `nextDate`.
    public let cycleDate: Date

    /// The rule's movements, latest first, then the lowest id, so every platform lists them alike.
    public static func payments(of rule: RecurringRule, in transactions: [Transaction]) -> [Transaction] {
        transactions.filter { $0.recurringID == rule.id }.sorted(by: latestFirst)
    }

    static func latestFirst(_ lhs: Transaction, _ rhs: Transaction) -> Bool {
        lhs.date != rhs.date ? lhs.date > rhs.date : lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
    }

    /// The confirmed movement of the rule that pays a cycle: dated from two calendar days before the
    /// cycle's occurrence (a manual payment may come early, as in `manualPayment`) up to two days
    /// before the next one. The latest one when there are several.
    public static func payment(
        of rule: RecurringRule,
        cycle: (start: Date, end: Date),
        in transactions: [Transaction],
        calendar: Calendar,
    ) -> Transaction? {
        let early = -RecurringSchedule.manualPaymentDaysBefore
        guard let first = calendar.date(byAdding: .day, value: early, to: calendar.startOfDay(for: cycle.start)),
              let end = calendar.date(byAdding: .day, value: early, to: calendar.startOfDay(for: cycle.end)) else { return nil }
        return payments(of: rule, in: transactions).first { transaction in
            let day = calendar.startOfDay(for: transaction.date)
            return transaction.isConfirmed && day >= first && day < end
        }
    }

    /// Whether the rule is paid, has something waiting, and when it's next due.
    public static func of(_ rule: RecurringRule, transactions: [Transaction], today: Date, calendar: Calendar) -> Self {
        let linked = payments(of: rule, in: transactions)
        let todayStart = calendar.startOfDay(for: today)
        let finished = RecurringSchedule.isFinished(rule, calendar: calendar)
        let cycle = RecurringSchedule.cycle(of: rule, endingAt: rule.nextDate, calendar: calendar)
        let payment = cycle.flatMap { Self.payment(of: rule, cycle: $0, in: transactions, calendar: calendar) }
        // The oldest draft dated today or before: the one most overdue.
        let draft = linked.last { !$0.isConfirmed && calendar.startOfDay(for: $0.date) <= todayStart }
        let daysOverdue = draft.map { max(0, days(from: $0.date, to: today, calendar: calendar)) } ?? 0
        let state: State = if draft != nil {
            daysOverdue > 0 ? .overdue : .toConfirm
        } else if rule.isPaused {
            .paused
        } else if finished {
            .ended
        } else {
            payment == nil ? .upcoming : .paid
        }
        return Self(
            state: state,
            nextDate: finished ? nil : rule.nextDate,
            daysUntilNext: finished ? nil : days(from: today, to: rule.nextDate, calendar: calendar),
            draft: draft,
            daysOverdue: daysOverdue,
            payment: payment,
            lastPayment: linked.first(where: \.isConfirmed),
            cycleDate: cycle?.start ?? rule.nextDate,
        )
    }

    private static func days(from: Date, to: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 0
    }
}

/// What a rule has been paid with: its detail's list and the figures above it.
public struct RecurringHistory: Hashable, Sendable {
    public struct PriceChange: Hashable, Sendable {
        public let from: Money
        public let to: Money
        /// The first payment at the new amount.
        public let transaction: Transaction
    }

    /// Every movement linked to the rule, drafts included, latest first.
    public let payments: [Transaction]
    /// How many of them are confirmed.
    public let paidCount: Int
    /// Confirmed payments of today's calendar year in the rule's currency.
    public let paidThisYear: Money
    /// Set when the latest confirmed payment's amount differs from the one before it.
    public let priceChange: PriceChange?

    public static func of(_ rule: RecurringRule, transactions: [Transaction], today: Date, calendar: Calendar) -> Self {
        let payments = RecurringStatus.payments(of: rule, in: transactions)
        let confirmed = payments.filter { $0.isConfirmed && $0.currency == rule.currency }
        let year = calendar.component(.year, from: today)
        let paidThisYear = confirmed
            .filter { calendar.component(.year, from: $0.date) == year }
            .reduce(Decimal.zero) { $0 + $1.amount }
        var priceChange: PriceChange?
        if confirmed.count >= 2, confirmed[0].amount != confirmed[1].amount {
            priceChange = PriceChange(
                from: Money(confirmed[1].amount, rule.currency),
                to: Money(confirmed[0].amount, rule.currency),
                transaction: confirmed[0],
            )
        }
        return Self(
            payments: payments,
            paidCount: payments.count(where: \.isConfirmed),
            paidThisYear: Money(paidThisYear, rule.currency),
            priceChange: priceChange,
        )
    }
}

extension RecurringStatus {
    /// Movements worth offering under "Link a payment": confirmed, linked to no rule, of the rule's
    /// kind and currency (and destination, for a transfer), whose amount is within 7.5 % of the
    /// rule's or whose description names the rule (either contains the other). Any account or card:
    /// a subscription is sometimes paid with another one. Likeliest first: the ones that name the
    /// rule, then the closest amount, then the latest, so "Grok $15" comes before a $15.82 dinner.
    public static func paymentCandidates(for rule: RecurringRule, in transactions: [Transaction]) -> [Transaction] {
        let name = CategorizationRules.folded(rule.name.trimmingCharacters(in: .whitespacesAndNewlines))
        let tolerance = abs(rule.amount) * RecurringSchedule.manualPaymentTolerance
        func names(_ transaction: Transaction) -> Bool {
            let description = CategorizationRules.folded(transaction.description.trimmingCharacters(in: .whitespacesAndNewlines))
            return !name.isEmpty && !description.isEmpty && (description.contains(name) || name.contains(description))
        }
        return transactions.filter { transaction in
            guard transaction.recurringID == nil, transaction.isConfirmed,
                  transaction.kind == rule.kind, transaction.currency == rule.currency else { return false }
            if rule.kind == .transfer, transaction.destinationAccountID != rule.destinationAccountID {
                return false
            }
            return names(transaction) || abs(transaction.amount - rule.amount) <= tolerance
        }
        .sorted { lhs, rhs in
            let (lhsNamed, rhsNamed) = (names(lhs), names(rhs))
            if lhsNamed != rhsNamed {
                return lhsNamed
            }
            let (lhsDistance, rhsDistance) = (abs(lhs.amount - rule.amount), abs(rhs.amount - rule.amount))
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            return latestFirst(lhs, rhs)
        }
    }

    /// Whether a movement can be linked to the rule by hand: same kind, and not another rule's.
    public static func canLink(_ transaction: Transaction, to rule: RecurringRule) -> Bool {
        transaction.kind == rule.kind && (transaction.recurringID == nil || transaction.recurringID == rule.id)
    }
}

/// "3 of 8 paid this month": the active expense rules due in today's calendar month and how many
/// are paid. A rule counts when its next date is in the month (not paid yet), or when the occurrence
/// before it is and it is either paid or left a draft waiting. A past occurrence with neither is not
/// counted as owed: the rule may have been set up after it, and nothing ever asked for it.
public struct RecurringMonthProgress: Hashable, Sendable {
    public let total: Int
    public let paid: Int
    /// What's left to pay this month, one amount per currency (never summed across), by code.
    public let remaining: [Money]

    public static func of(_ rules: [RecurringRule], transactions: [Transaction], today: Date, calendar: Calendar) -> Self {
        let month = calendar.dateComponents([.year, .month], from: today)
        func inMonth(_ date: Date) -> Bool {
            calendar.dateComponents([.year, .month], from: date) == month
        }
        var remaining: [String: Decimal] = [:]
        var total = 0
        var paid = 0
        for rule in rules where rule.kind == .expense && RecurringSchedule.isActive(rule, calendar: calendar) {
            let status = RecurringStatus.of(rule, transactions: transactions, today: today, calendar: calendar)
            if let next = status.nextDate, inMonth(next) {
                total += 1
                remaining[rule.currency, default: 0] += rule.amount
            } else if inMonth(status.cycleDate) {
                if status.state == .paid {
                    total += 1
                    paid += 1
                } else if status.draft != nil {
                    total += 1
                    remaining[rule.currency, default: 0] += rule.amount
                }
            }
        }
        return Self(
            total: total,
            paid: paid,
            remaining: remaining.keys.sorted().map { Money(remaining[$0] ?? 0, $0) },
        )
    }
}
