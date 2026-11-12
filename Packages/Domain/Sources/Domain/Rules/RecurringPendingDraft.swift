import Foundation

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

extension RecurringSchedule {
    /// The draft a rule left waiting (`recurringID` the rule's, still `planned`) whose calendar day
    /// is today or earlier: the oldest one, since that's the one most overdue. A draft for a later
    /// day isn't due yet. The Recurring row shows it in place of the next date. Mirrors the web's
    /// `pendingDraftOf`.
    public static func pendingDraft(
        of rule: RecurringRule,
        in transactions: [Transaction],
        today: Date,
        calendar: Calendar,
    ) -> PendingRuleDraft? {
        let todayStart = calendar.startOfDay(for: today)
        let oldest = transactions
            .filter { $0.recurringID == rule.id && $0.status == .planned && calendar.startOfDay(for: $0.date) <= todayStart }
            .min { ($0.date, $0.id.uuidString.lowercased()) < ($1.date, $1.id.uuidString.lowercased()) }
        guard let oldest else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: oldest.date), to: todayStart).day ?? 0
        return PendingRuleDraft(transaction: oldest, daysOverdue: days)
    }
}
