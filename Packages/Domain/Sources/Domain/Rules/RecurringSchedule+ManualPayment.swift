import Foundation

extension RecurringSchedule {
    /// How far a manual payment's amount may be from the rule's: 7.5 % either way.
    public static let manualPaymentTolerance = Decimal(string: "0.075") ?? 0
    /// How many calendar days before the occurrence a manual payment still counts for it.
    public static let manualPaymentDaysBefore = 2

    /// The movement that already pays the occurrence on `date`, if any: typed by hand (or linked to
    /// this rule) with the rule's kind, account, currency, card (when the rule has one) and
    /// destination (transfers), an amount within 7.5 % of the rule's, dated from two calendar days
    /// before the occurrence through its day, and not in `taken` (a movement pays one occurrence
    /// only). A movement linked to another rule never counts. Among several, the closest amount wins,
    /// then the closest date, then the lowest id, so iOS, web and the server pick the same one.
    public static func manualPayment(
        for rule: RecurringRule,
        on date: Date,
        in transactions: [Transaction],
        taken: Set<UUID>,
        calendar: Calendar,
    ) -> Transaction? {
        let lastDay = calendar.startOfDay(for: date)
        guard let firstDay = calendar.date(byAdding: .day, value: -manualPaymentDaysBefore, to: lastDay) else { return nil }
        let tolerance = abs(rule.amount) * manualPaymentTolerance
        var best: (transaction: Transaction, amountGap: Decimal, dateGap: TimeInterval)?
        for transaction in transactions where pays(transaction, rule, taken: taken) {
            let day = calendar.startOfDay(for: transaction.date)
            guard day >= firstDay, day <= lastDay else { continue }
            let amountGap = abs(transaction.amount - rule.amount)
            guard amountGap <= tolerance else { continue }
            let dateGap = abs(date.timeIntervalSince(transaction.date))
            if let current = best {
                let closer = amountGap < current.amountGap
                    || (amountGap == current.amountGap && (dateGap < current.dateGap
                            || (dateGap == current.dateGap && transaction.id.uuidString < current.transaction.id.uuidString)))
                guard closer else { continue }
            }
            best = (transaction, amountGap, dateGap)
        }
        return best?.transaction
    }

    /// Everything but the date and the amount: same kind, account, currency, card and destination,
    /// not linked to another rule and not already paying another occurrence.
    private static func pays(_ transaction: Transaction, _ rule: RecurringRule, taken: Set<UUID>) -> Bool {
        guard !taken.contains(transaction.id) else { return false }
        if let linked = transaction.recurringID, linked != rule.id {
            return false
        }
        guard transaction.kind == rule.kind, transaction.accountID == rule.accountID,
              transaction.currency == rule.currency else { return false }
        if let card = rule.cardID, transaction.cardID != card {
            return false
        }
        if rule.kind == .transfer, transaction.destinationAccountID != rule.destinationAccountID {
            return false
        }
        return true
    }
}
