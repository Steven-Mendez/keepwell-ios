import Foundation
import Testing
@testable import Domain

/// Same cases as the web's "A rule's pending draft" (`tests/domain/recurring.test.ts`), derived
/// from the same list home reads: the drafts through today, indexed by their rule.
@Suite("A rule's pending draft")
struct RecurringPendingDraftTests {
    private let calendar = Fixtures.calendar
    private let today = Fixtures.date(2026, 11, 12, hour: 15)
    private let rule = RecurringRule(
        name: "Streaming",
        kind: .expense,
        categoryID: "subscriptions",
        amount: Fixtures.decimal("10"),
        currency: "USD",
        accountID: UUID(),
        frequency: .monthly,
        interval: 1,
        startDate: Fixtures.date(2026, 1, 31, hour: 9),
    )

    private func draft(_ date: Date, rule ruleID: UUID?? = nil, status: TransactionStatus = .planned) -> Transaction {
        Transaction(
            date: date,
            status: status,
            description: "Streaming",
            kind: .expense,
            categoryID: "subscriptions",
            amount: Fixtures.decimal("10"),
            currency: "USD",
            accountID: UUID(),
            exchangeRate: Fixtures.usdNio,
            recurringID: ruleID ?? rule.id,
        )
    }

    private func pending(_ transactions: [Transaction], today: Date? = nil) -> PendingRuleDraft? {
        let payments = UpcomingPayments.compute(
            UpcomingPayments.Ledger(transactions: transactions),
            on: today ?? self.today,
            days: 0,
            calendar: calendar,
        )
        return UpcomingPayments.pendingRuleDrafts(payments)[rule.id]
    }

    @Test
    func noneWithoutADraftDueTodayOrBefore() {
        #expect(pending([]) == nil)
        #expect(pending([draft(Fixtures.date(2026, 11, 13, hour: 9))]) == nil)
    }

    @Test
    func ignoresConfirmedMovementsOtherRulesAndDraftsWithNoRule() {
        let day = Fixtures.date(2026, 11, 10)
        let movements = [
            draft(day, status: .confirmed),
            draft(day, rule: .some(UUID())),
            draft(day, rule: .some(nil)),
        ]
        #expect(pending(movements) == nil)
    }

    @Test
    func todaysDraftIsZeroDaysOverdueWhateverItsTime() {
        let later = draft(Fixtures.date(2026, 11, 12, hour: 23))
        #expect(pending([later]) == PendingRuleDraft(transaction: later, daysOverdue: 0))
    }

    @Test
    func theOldestOverdueDraftWithCalendarDaysSinceItsDate() {
        let older = draft(Fixtures.date(2026, 11, 9, hour: 23))
        let newer = draft(Fixtures.date(2026, 11, 11, hour: 1))
        let notYet = draft(Fixtures.date(2026, 11, 20))
        #expect(pending([newer, older, notYet]) == PendingRuleDraft(transaction: older, daysOverdue: 3))
    }

    @Test
    func countsCalendarDaysAcrossAMonthEnd() {
        let old = draft(Fixtures.date(2026, 10, 31, hour: 9))
        #expect(pending([old], today: Fixtures.date(2026, 11, 2, hour: 8))?.daysOverdue == 2)
    }
}
