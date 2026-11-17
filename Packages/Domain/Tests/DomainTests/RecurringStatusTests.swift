import Foundation
import Testing
@testable import Domain

/// Whether a recurring rule is paid, what paid it and when it's next due (keepwell-web
/// `recurring-status.test.ts`).
@Suite("Recurring rule status")
struct RecurringStatusTests {
    private let calendar = Fixtures.calendar
    private let account = UUID()
    private let ruleID = UUID(uuidString: "00000000-0000-0000-0000-00000000E030") ?? UUID()
    private let otherRuleID = UUID(uuidString: "00000000-0000-0000-0000-00000000F030") ?? UUID()
    private let today = Fixtures.date(2026, 11, 16)

    /// Created on 16 Nov to start on 1 Dec, as a rule proposed from the MCP is.
    private func music(
        id: UUID? = nil,
        name: String = "Apple Music",
        _ kind: TransactionKind = .expense,
        amount: String = "6.49",
        currency: String = "USD",
        interval: Int = 1,
        start: Date = Fixtures.date(2026, 12, 1, hour: 9),
        next: Date? = nil,
        end: Date? = nil,
        isPaused: Bool = false,
    ) -> RecurringRule {
        RecurringRule(
            id: id ?? ruleID,
            name: name,
            kind: kind,
            categoryID: kind == .income ? "salary" : "subscriptions",
            amount: Fixtures.decimal(amount),
            currency: currency,
            accountID: account,
            frequency: .monthly,
            interval: interval,
            startDate: start,
            nextDate: next ?? start,
            endDate: end,
            isPaused: isPaused,
        )
    }

    private func payment(
        _ kind: TransactionKind = .expense,
        amount: String = "6.49",
        currency: String = "USD",
        description: String = "APPLE.COM/BILL Apple Music",
        date: Date = Fixtures.date(2026, 11, 1),
        status: TransactionStatus = .confirmed,
        rule: UUID?? = .none,
    ) -> Transaction {
        Transaction(
            date: date,
            status: status,
            description: description,
            kind: kind,
            categoryID: kind == .income ? "salary" : "subscriptions",
            amount: Fixtures.decimal(amount),
            currency: currency,
            accountID: account,
            exchangeRate: Fixtures.usdNio,
            recurringID: rule ?? ruleID,
        )
    }

    private func status(_ rule: RecurringRule, _ transactions: [Transaction], today: Date? = nil) -> RecurringStatus {
        RecurringStatus.of(rule, transactions: transactions, today: today ?? self.today, calendar: calendar)
    }

    @Test
    func aRuleWithNothingLinkedIsUpcomingWithTheDaysLeft() {
        let result = status(music(), [])
        #expect(result.state == .upcoming)
        #expect(result.daysUntilNext == 15)
        #expect(result.lastPayment == nil)
    }

    @Test
    func aRuleThatHasNotStartedIsPaidByAPaymentOfTheCycleBeforeItsStart() {
        let paid = payment()
        let result = status(music(), [paid])
        #expect(result.state == .paid)
        #expect(result.payment?.id == paid.id)
        #expect(result.cycleDate == Fixtures.date(2026, 11, 1, hour: 9))
        #expect(result.daysUntilNext == 15)
    }

    @Test
    func aPaymentOfAnEarlierCycleStaysAsTheLastPaymentOnly() {
        let old = payment(date: Fixtures.date(2026, 10, 1))
        let result = status(music(), [old])
        #expect(result.state == .upcoming)
        #expect(result.lastPayment?.id == old.id)
    }

    @Test
    func aPaymentUpToTwoDaysEarlyPaysTheCycle() {
        #expect(status(music(), [payment(date: Fixtures.date(2026, 10, 30))]).state == .paid)
        #expect(status(music(), [payment(date: Fixtures.date(2026, 10, 29))]).state == .upcoming)
        // Paid on 29 Nov for the 1 Dec occurrence: it pays the next cycle, not November's.
        #expect(status(music(), [payment(date: Fixtures.date(2026, 11, 29))], today: Fixtures.date(2026, 11, 30)).state == .upcoming)
    }

    @Test
    func aDraftWaitsOrIsOverdueTheOldestFirst() {
        let rule = music(start: Fixtures.date(2026, 10, 16, hour: 9), next: Fixtures.date(2026, 12, 16, hour: 9))
        let todays = payment(date: Fixtures.date(2026, 11, 16, hour: 9), status: .planned)
        let waiting = status(rule, [todays])
        #expect(waiting.state == .toConfirm)
        #expect(waiting.daysOverdue == 0)
        let older = payment(date: Fixtures.date(2026, 10, 16, hour: 9), status: .planned)
        let overdue = status(rule, [todays, older])
        #expect(overdue.state == .overdue)
        #expect(overdue.daysOverdue == 31)
        #expect(overdue.draft?.id == older.id)
        // A draft for a later day isn't due yet.
        #expect(status(music(), [payment(date: Fixtures.date(2026, 12, 1, hour: 9), status: .planned)]).state == .upcoming)
    }

    @Test
    func pausedAndEndedRulesSaySoEvenWhenPaid() {
        #expect(status(music(isPaused: true), [payment()]).state == .paused)
        let ended = status(
            music(start: Fixtures.date(2026, 9, 1, hour: 9), next: Fixtures.date(2026, 12, 1, hour: 9), end: Fixtures.date(2026, 11, 15)),
            [payment()],
        )
        #expect(ended.state == .ended)
        #expect(ended.nextDate == nil)
    }

    @Test
    func aQuarterlyRuleIsPaidByTheChargeThreeMonthsBeforeItsNextDate() {
        let mobbin = music(name: "Mobbin", amount: "22.5", interval: 3, start: Fixtures.date(2027, 1, 31, hour: 9))
        let result = status(mobbin, [payment(amount: "22.5", date: Fixtures.date(2026, 10, 31))])
        #expect(result.state == .paid)
        #expect(result.cycleDate == Fixtures.date(2026, 10, 31, hour: 9))
    }

    @Test
    func onlyThisRulesMovementsCount() {
        #expect(status(music(), [payment(rule: otherRuleID), payment(rule: .some(nil))]).state == .upcoming)
    }

    @Test
    func theHistoryListsLatestFirstWithThisYearsTotalAndThePriceChange() {
        let transactions = [
            payment(amount: "5.99", date: Fixtures.date(2025, 12, 1)),
            payment(amount: "5.99", date: Fixtures.date(2026, 10, 1)),
            payment(date: Fixtures.date(2026, 11, 1)),
            payment(date: Fixtures.date(2026, 12, 1), status: .planned),
        ]
        let history = RecurringHistory.of(music(), transactions: transactions, today: today, calendar: calendar)
        #expect(history.payments.map(\.id) == transactions.reversed().map(\.id))
        #expect(history.paidCount == 3)
        #expect(history.paidThisYear == Money(Fixtures.decimal("12.48"), "USD"))
        #expect(history.priceChange?.from.amount == Fixtures.decimal("5.99"))
        #expect(history.priceChange?.to.amount == Fixtures.decimal("6.49"))
        let steady = RecurringHistory.of(
            music(),
            transactions: [payment(), payment(date: Fixtures.date(2026, 10, 1))],
            today: today,
            calendar: calendar,
        )
        #expect(steady.priceChange == nil)
    }

    @Test
    func candidatesMatchByAmountOrByName() {
        let byAmount = payment(description: "Compra", date: Fixtures.date(2026, 10, 1), rule: .some(nil))
        let byName = payment(amount: "10.99", description: "apple music familiar", rule: .some(nil))
        let candidates = RecurringStatus.paymentCandidates(for: music(), in: [
            byAmount,
            byName,
            payment(amount: "50", description: "Supermercado", rule: .some(nil)),
            payment(currency: "NIO", rule: .some(nil)),
            payment(status: .planned, rule: .some(nil)),
            payment(rule: otherRuleID),
            payment(),
        ])
        #expect(candidates.map(\.id) == [byName.id, byAmount.id])
    }

    @Test
    func theMovementThatNamesTheRuleComesFirstThenTheClosestAmountThenTheLatest() {
        let grok = music(name: "Grok", amount: "15")
        let candidates = RecurringStatus.paymentCandidates(for: grok, in: [
            payment(amount: "15.82", description: "KFC", date: Fixtures.date(2026, 11, 8), rule: .some(nil)),
            payment(amount: "13.99", description: "Pizza", date: Fixtures.date(2026, 11, 7), rule: .some(nil)),
            payment(amount: "15", description: "Grok", date: Fixtures.date(2026, 11, 4), rule: .some(nil)),
            payment(amount: "15", description: "Pago", date: Fixtures.date(2026, 10, 4), rule: .some(nil)),
        ])
        #expect(candidates.map(\.description) == ["Grok", "Pago", "KFC", "Pizza"])
    }

    @Test
    func aManualPaymentThatCoversAnOccurrenceIsLinkedToTheRule() {
        let rule = music(start: Fixtures.date(2026, 10, 16, hour: 9), next: Fixtures.date(2026, 11, 16, hour: 9))
        let manual = payment(date: Fixtures.date(2026, 11, 15), rule: .some(nil))
        let evening = Fixtures.date(2026, 11, 16, hour: 20)
        let result = RecurringSchedule.materialize(
            [rule],
            transactions: [manual],
            today: evening,
            exchangeRate: Fixtures.usdNio,
            calendar: calendar,
        )
        #expect(result.transactions.isEmpty)
        #expect(result.linked.map(\.id) == [manual.id])
        #expect(result.linked.first?.recurringID == ruleID)
        let moved = try? #require(result.rules.first)
        let after = moved.map { status($0, result.linked, today: evening) }
        #expect(after?.state == .paid)
        #expect(after?.daysUntilNext == 30)
        // Already linked: nothing to write again.
        let again = RecurringSchedule.materialize(
            [rule],
            transactions: result.linked,
            today: evening,
            exchangeRate: Fixtures.usdNio,
            calendar: calendar,
        )
        #expect(again.linked.isEmpty)
    }

    @Test
    func theMonthCountsWhatIsDueAndWhatIsPaidPerCurrency() {
        let light = music(
            id: otherRuleID,
            name: "Luz",
            amount: "1200",
            currency: "NIO",
            start: Fixtures.date(2026, 10, 25, hour: 9),
            next: Fixtures.date(2026, 11, 25, hour: 9),
        )
        let salary = music(
            id: UUID(),
            name: "Salario",
            .income,
            start: Fixtures.date(2026, 10, 25, hour: 9),
            next: Fixtures.date(2026, 11, 25, hour: 9),
        )
        let notStarted = music(id: UUID(), name: "Grok", start: Fixtures.date(2026, 12, 4, hour: 9))
        let paused = music(
            id: UUID(),
            name: "Pausada",
            start: Fixtures.date(2026, 10, 25, hour: 9),
            next: Fixtures.date(2026, 11, 25, hour: 9),
            isPaused: true,
        )
        // Its 5 Nov occurrence passed with no payment and no draft: set up later, so nothing is owed for it.
        let setUpLater = music(
            id: UUID(),
            name: "Gym",
            amount: "30",
            start: Fixtures.date(2026, 10, 5, hour: 9),
            next: Fixtures.date(2026, 12, 5, hour: 9),
        )
        // Its 10 Nov occurrence left a draft that still waits.
        let waitingID = UUID()
        let waiting = music(
            id: waitingID,
            name: "Water",
            amount: "12",
            start: Fixtures.date(2026, 10, 10, hour: 9),
            next: Fixtures.date(2026, 12, 10, hour: 9),
        )
        let draft = payment(amount: "12", date: Fixtures.date(2026, 11, 10, hour: 9), status: .planned, rule: waitingID)
        let progress = RecurringMonthProgress.of(
            [music(), light, salary, notStarted, setUpLater, waiting, paused],
            transactions: [payment(), draft],
            today: today,
            calendar: calendar,
        )
        #expect(progress.total == 3)
        #expect(progress.paid == 1)
        #expect(progress.remaining == [Money(Fixtures.decimal("1200"), "NIO"), Money(Fixtures.decimal("12"), "USD")])
    }
}
