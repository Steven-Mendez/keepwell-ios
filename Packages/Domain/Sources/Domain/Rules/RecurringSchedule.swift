import Foundation

/// One date a recurring rule falls on.
public struct RecurringOccurrence: Hashable, Sendable {
    public let rule: RecurringRule
    public let date: Date

    public init(rule: RecurringRule, date: Date) {
        self.rule = rule
        self.date = date
    }
}

/// When recurring rules fall and what they record. Pure functions, mirrored line by line by the
/// web app, so both platforms record the same movements on the same days.
///
/// Every occurrence is counted from the rule's `startDate` with the calendar's own arithmetic
/// (`date(byAdding:)`): Jan 31 + 1 month is Feb 28 (or 29), and Jan 31 + 2 months is Mar 31.
/// Chaining from the previous, clamped date would drift every rule to the 28th.
public enum RecurringSchedule {
    /// After months away, only the latest occurrences are recorded instead of a flood of drafts.
    public static let catchUpLimit = 12

    /// What a run of `materialize` records and which rules move on.
    public struct Materialization: Hashable, Sendable {
        public let transactions: [Transaction]
        /// Only the rules whose `nextDate` changed.
        public let rules: [RecurringRule]

        public var isEmpty: Bool {
            transactions.isEmpty && rules.isEmpty
        }
    }

    /// The `index`-th occurrence (0 is `startDate`), `startDate + index × interval × unit`.
    public static func occurrence(of rule: RecurringRule, _ index: Int, calendar: Calendar) -> Date? {
        let steps = index * rule.interval
        return switch rule.frequency {
        case .weekly: calendar.date(byAdding: .day, value: 7 * steps, to: rule.startDate)
        case .monthly: calendar.date(byAdding: .month, value: steps, to: rule.startDate)
        case .yearly: calendar.date(byAdding: .year, value: steps, to: rule.startDate)
        }
    }

    /// The first occurrence whose calendar day is `day`'s or later.
    public static func firstOccurrence(of rule: RecurringRule, onOrAfter day: Date, calendar: Calendar) -> Date? {
        let target = calendar.startOfDay(for: day)
        var index = max(estimatedIndex(of: rule, near: target, calendar: calendar), 0)
        // The estimate may land one step late because of clamping; step back while it still qualifies.
        while index > 0, let previous = occurrence(of: rule, index - 1, calendar: calendar),
              calendar.startOfDay(for: previous) >= target
        {
            index -= 1
        }
        while let date = occurrence(of: rule, index, calendar: calendar) {
            if calendar.startOfDay(for: date) >= target {
                return date
            }
            index += 1
        }
        return nil
    }

    /// The first occurrence on a calendar day after `date`'s.
    public static func firstOccurrence(of rule: RecurringRule, after date: Date, calendar: Calendar) -> Date? {
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) else { return nil }
        return firstOccurrence(of: rule, onOrAfter: nextDay, calendar: calendar)
    }

    /// Occurrences from `nextDate` on whose day has come (≤ `today`), none after `endDate`. A paused
    /// rule has none.
    public static func due(_ rule: RecurringRule, today: Date, calendar: Calendar) -> [Date] {
        guard !rule.isPaused else { return [] }
        let todayStart = calendar.startOfDay(for: today)
        return occurrences(of: rule, from: rule.nextDate, calendar: calendar) { calendar.startOfDay(for: $0) <= todayStart }
    }

    /// The occurrences still to come from `today` through `days` days later, soonest first, for
    /// home and reminders. Paused rules have none.
    public static func upcoming(_ rules: [RecurringRule], from today: Date, days: Int, calendar: Calendar) -> [RecurringOccurrence] {
        let todayStart = calendar.startOfDay(for: today)
        guard let limit = calendar.date(byAdding: .day, value: days, to: todayStart) else { return [] }
        return rules.filter { !$0.isPaused }.flatMap { rule in
            let from = max(rule.nextDate, todayStart)
            return occurrences(of: rule, from: from, calendar: calendar) { calendar.startOfDay(for: $0) <= limit }
                .map { RecurringOccurrence(rule: rule, date: $0) }
        }
        .sorted { ($0.date, $0.rule.name) < ($1.date, $1.rule.name) }
    }

    /// Occurrences not recorded yet, from `nextDate` through `lastDay`'s calendar day, none after
    /// `endDate`. A paused rule has none. The balance forecast counts these on top of the drafts
    /// already recorded, so nothing is counted twice.
    public static func pending(_ rule: RecurringRule, through lastDay: Date, calendar: Calendar) -> [Date] {
        guard !rule.isPaused else { return [] }
        let limit = calendar.startOfDay(for: lastDay)
        return occurrences(of: rule, from: rule.nextDate, calendar: calendar) { calendar.startOfDay(for: $0) <= limit }
    }

    /// The next `count` occurrences from `nextDate`, for a rule's detail.
    public static func next(_ count: Int, of rule: RecurringRule, calendar: Calendar) -> [Date] {
        var dates: [Date] = []
        var cursor = rule.nextDate
        while dates.count < count, let date = firstOccurrence(of: rule, onOrAfter: cursor, calendar: calendar),
              isWithinEnd(date, of: rule, calendar: calendar)
        {
            dates.append(date)
            guard let following = firstOccurrence(of: rule, after: date, calendar: calendar) else { break }
            cursor = following
        }
        return dates
    }

    /// What the rule costs per month, for totals only: monthly ÷ interval, weekly × 52 ÷ 12 ÷
    /// interval, yearly ÷ (12 × interval). Unrounded; screens round when they show it.
    public static func monthlyEquivalent(of rule: RecurringRule) -> Decimal {
        let interval = Decimal(max(rule.interval, 1))
        return switch rule.frequency {
        case .monthly: rule.amount / interval
        case .weekly: rule.amount * 52 / 12 / interval
        case .yearly: rule.amount / (12 * interval)
        }
    }

    /// `nextDate` after the person changes when a rule starts or how often it repeats: the first
    /// occurrence from today (or the start, if later). Movements already recorded stay as they are.
    public static func rescheduledNextDate(of rule: RecurringRule, today: Date, calendar: Calendar) -> Date {
        firstOccurrence(of: rule, onOrAfter: max(today, rule.startDate), calendar: calendar) ?? rule.startDate
    }

    /// Records every due occurrence of the active rules as a movement, at most `catchUpLimit` per
    /// rule (the latest ones). An occurrence is skipped when a movement of the same rule already
    /// sits on that day, so two devices, or a restore, never record it twice. Each rule then moves
    /// to its first occurrence after the last one recorded (or after today, when all were skipped).
    public static func materialize(
        _ rules: [RecurringRule],
        transactions: [Transaction],
        today: Date,
        exchangeRate: ExchangeRate,
        calendar: Calendar,
        makeID: () -> UUID = UUID.init,
    ) -> Materialization {
        var recordedDays: [UUID: Set<Date>] = [:]
        for transaction in transactions {
            guard let ruleID = transaction.recurringID else { continue }
            recordedDays[ruleID, default: []].insert(calendar.startOfDay(for: transaction.date))
        }
        var created: [Transaction] = []
        var advanced: [RecurringRule] = []
        for rule in rules {
            let dates = due(rule, today: today, calendar: calendar).suffix(catchUpLimit)
            guard !dates.isEmpty else { continue }
            var lastRecorded: Date?
            for date in dates where !(recordedDays[rule.id]?.contains(calendar.startOfDay(for: date)) ?? false) {
                created.append(movement(from: rule, on: date, exchangeRate: exchangeRate, id: makeID()))
                recordedDays[rule.id, default: []].insert(calendar.startOfDay(for: date))
                lastRecorded = date
            }
            let next = firstOccurrence(of: rule, after: lastRecorded ?? today, calendar: calendar) ?? rule.nextDate
            if next != rule.nextDate {
                advanced.append(rule.with(nextDate: next))
            }
        }
        return Materialization(transactions: created, rules: advanced)
    }

    /// The movement a rule records on `date`, at today's rate like any new movement.
    public static func movement(from rule: RecurringRule, on date: Date, exchangeRate: ExchangeRate, id: UUID = UUID()) -> Transaction {
        Transaction(
            id: id,
            date: date,
            status: rule.autoConfirm ? .confirmed : .planned,
            description: rule.name,
            kind: rule.kind,
            categoryID: rule.kind == .transfer ? nil : rule.categoryID,
            amount: rule.amount,
            currency: rule.currency,
            accountID: rule.accountID,
            cardID: rule.cardID,
            destinationAccountID: rule.kind == .transfer ? rule.destinationAccountID : nil,
            exchangeRate: exchangeRate,
            isShared: false,
            note: rule.note,
            recurringID: rule.id,
        )
    }

    // MARK: - Private

    /// Occurrences from `start`'s day on, while `isIncluded` holds and the end isn't passed.
    private static func occurrences(
        of rule: RecurringRule,
        from start: Date,
        calendar: Calendar,
        while isIncluded: (Date) -> Bool,
    ) -> [Date] {
        var dates: [Date] = []
        var cursor = start
        while let date = firstOccurrence(of: rule, onOrAfter: cursor, calendar: calendar),
              isIncluded(date), isWithinEnd(date, of: rule, calendar: calendar)
        {
            dates.append(date)
            guard let following = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) else { break }
            cursor = following
        }
        return dates
    }

    private static func isWithinEnd(_ date: Date, of rule: RecurringRule, calendar: Calendar) -> Bool {
        guard let endDate = rule.endDate else { return true }
        return calendar.startOfDay(for: date) <= calendar.startOfDay(for: endDate)
    }

    /// Roughly how many steps from the start `target` is, so far-off dates don't walk every step.
    private static func estimatedIndex(of rule: RecurringRule, near target: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: rule.startDate)
        guard target > start else { return 0 }
        let steps = switch rule.frequency {
        case .weekly: (calendar.dateComponents([.day], from: start, to: target).day ?? 0) / 7
        case .monthly: calendar.dateComponents([.month], from: start, to: target).month ?? 0
        case .yearly: calendar.dateComponents([.year], from: start, to: target).year ?? 0
        }
        return steps / max(rule.interval, 1)
    }
}
