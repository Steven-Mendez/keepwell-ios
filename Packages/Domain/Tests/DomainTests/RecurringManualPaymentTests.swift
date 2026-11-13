import Foundation
import Testing
@testable import Domain

/// T29: a movement typed by hand for an occurrence the rule would then record on its own counts as
/// that occurrence (keepwell-web `recurring-manual-payment.test.ts`).
@Suite("Manual payment of a recurring occurrence")
struct RecurringManualPaymentTests {
    private let calendar = Fixtures.calendar
    private let account = UUID()
    private let otherAccount = UUID()
    private let card = UUID()
    private let otherCard = UUID()
    private let ruleID = UUID(uuidString: "00000000-0000-0000-0000-00000000E029") ?? UUID()
    private let otherRuleID = UUID(uuidString: "00000000-0000-0000-0000-00000000F029") ?? UUID()

    private func rent(
        id: UUID? = nil,
        _ kind: TransactionKind = .expense,
        amount: String = "500",
        card ruleCard: UUID?? = .none,
        destination: UUID? = nil,
        frequency: RecurringFrequency = .monthly,
        start: Date = Fixtures.date(2026, 10, 1, hour: 9),
        next: Date = Fixtures.date(2026, 11, 1, hour: 9),
        autoConfirm: Bool = true,
    ) -> RecurringRule {
        RecurringRule(
            id: id ?? ruleID,
            name: "Rent",
            kind: kind,
            categoryID: kind == .transfer ? nil : "housing",
            amount: Fixtures.decimal(amount),
            currency: "USD",
            accountID: account,
            cardID: ruleCard ?? card,
            destinationAccountID: destination,
            frequency: frequency,
            startDate: start,
            nextDate: next,
            autoConfirm: autoConfirm,
        )
    }

    private func manual(
        _ kind: TransactionKind = .expense,
        amount: String = "500",
        currency: String = "USD",
        account payer: UUID? = nil,
        card payerCard: UUID?? = .none,
        destination: UUID? = nil,
        date: Date = Fixtures.date(2026, 10, 30),
        recurringID: UUID? = nil,
        id: UUID = UUID(),
    ) -> Transaction {
        Transaction(
            id: id,
            date: date,
            description: "Alquiler",
            kind: kind,
            categoryID: kind == .transfer ? nil : "housing",
            amount: Fixtures.decimal(amount),
            currency: currency,
            accountID: payer ?? account,
            cardID: payerCard ?? card,
            destinationAccountID: destination,
            exchangeRate: Fixtures.usdNio,
            recurringID: recurringID,
        )
    }

    private func run(
        _ rules: [RecurringRule],
        _ transactions: [Transaction],
        today: Date = Fixtures.date(2026, 11, 1, hour: 20),
    ) -> RecurringSchedule.Materialization {
        RecurringSchedule.materialize(rules, transactions: transactions, today: today, exchangeRate: Fixtures.usdNio, calendar: calendar)
    }

    /// True when the manual payment covered the rule's occurrence on 1 Nov.
    private func covers(_ payment: Transaction, _ rule: RecurringRule? = nil, today: Date = Fixtures.date(2026, 11, 1, hour: 20)) -> Bool {
        run([rule ?? rent()], [payment], today: today).transactions.isEmpty
    }

    private func day(_ date: Date?) -> DateComponents? {
        date.map { calendar.dateComponents([.year, .month, .day, .hour], from: $0) }
    }

    @Test
    func theManualPaymentCountsAsTheOccurrenceAndTheRuleMovesOn() {
        let result = run([rent()], [manual()])
        #expect(result.transactions.isEmpty)
        #expect(result.rules.map { day($0.nextDate) } == [DateComponents(year: 2026, month: 12, day: 1, hour: 9)])
    }

    @Test
    func aRuleWithoutAutomaticConfirmationLeavesNoDraftEither() {
        #expect(covers(manual(), rent(autoConfirm: false)))
    }

    @Test
    func countsFromTwoCalendarDaysBeforeThroughTheOccurrencesDay() {
        #expect(covers(manual(date: Fixtures.date(2026, 10, 30, hour: 0))))
        #expect(covers(manual(date: Fixtures.date(2026, 11, 1, hour: 23))))
        #expect(!covers(manual(date: Fixtures.date(2026, 10, 29, hour: 23))))
        // Typed the day after: the occurrence already exists by then (out of scope).
        #expect(!covers(manual(date: Fixtures.date(2026, 11, 2, hour: 8)), today: Fixtures.date(2026, 11, 2, hour: 20)))
    }

    @Test
    func allowsTheAmountToDifferBySevenAndAHalfPercentNoMore() {
        #expect(covers(manual(amount: "537.50")))
        #expect(covers(manual(amount: "462.50")))
        #expect(!covers(manual(amount: "538")))
        #expect(!covers(manual(amount: "462")))
    }

    @Test
    func needsTheRulesAccountCurrencyKindAndCard() {
        #expect(!covers(manual(account: otherAccount)))
        #expect(!covers(manual(currency: "NIO")))
        #expect(!covers(manual(.income)))
        #expect(!covers(manual(card: otherCard)))
        // A rule paid from the account (no card) accepts any card of that account.
        #expect(covers(manual(card: otherCard), rent(card: .some(nil))))
    }

    @Test
    func neverTakesAMovementLinkedToAnotherRule() {
        #expect(!covers(manual(recurringID: otherRuleID)))
        #expect(covers(manual(recurringID: ruleID)))
    }

    @Test
    func onePaymentCoversOneOccurrenceOfAWeeklyRule() {
        let weekly = rent(frequency: .weekly, start: Fixtures.date(2026, 10, 25, hour: 9))
        let result = run([weekly], [manual(date: Fixtures.date(2026, 10, 31))], today: Fixtures.date(2026, 11, 8, hour: 20))
        #expect(result.transactions.map { day($0.date) } == [DateComponents(year: 2026, month: 11, day: 8, hour: 9)])
        #expect(result.rules.map { day($0.nextDate) } == [DateComponents(year: 2026, month: 11, day: 15, hour: 9)])
    }

    @Test
    func twoRulesWithTheSameAmountAndAccountTheLowerIDTakesThePayment() {
        let result = run([rent(id: otherRuleID), rent()], [manual()])
        #expect(result.transactions.map(\.recurringID) == [otherRuleID])
        #expect(result.rules.count == 2)
    }

    @Test
    func appliesToTransfersWithTheSameDestinationAndToIncome() {
        let cash = UUID()
        let transfer = rent(.transfer, card: .some(nil), destination: cash)
        #expect(covers(manual(.transfer, card: .some(nil), destination: cash), transfer))
        #expect(!covers(manual(.transfer, card: .some(nil), destination: otherAccount), transfer))
        let salary = rent(.income, amount: "1200", card: .some(nil))
        #expect(covers(manual(.income, amount: "1180", card: .some(nil)), salary))
    }

    @Test
    func picksTheClosestAmountThenDateThenLowestIDAndSkipsTakenOnes() throws {
        let due = Fixtures.date(2026, 11, 1, hour: 9)
        let id = { (suffix: String) in try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000\(suffix)")) }
        let near = try manual(amount: "505", date: Fixtures.date(2026, 10, 30), id: id("B2"))
        let far = try manual(amount: "520", date: Fixtures.date(2026, 11, 1), id: id("B1"))
        let pick = { (transactions: [Transaction], taken: Set<UUID>) in
            RecurringSchedule.manualPayment(for: rent(), on: due, in: transactions, taken: taken, calendar: calendar)?.id
        }
        #expect(pick([far, near], []) == near.id)
        let sameAmountLater = try manual(amount: "505", date: Fixtures.date(2026, 10, 31), id: id("B3"))
        #expect(pick([near, sameAmountLater], []) == sameAmountLater.id)
        let twin = try manual(amount: "505", date: Fixtures.date(2026, 10, 30), id: id("B0"))
        #expect(pick([near, twin], []) == twin.id)
        #expect(pick([near, twin], [twin.id]) == near.id)
    }
}
