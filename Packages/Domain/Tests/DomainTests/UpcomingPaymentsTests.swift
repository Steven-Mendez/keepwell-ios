import Foundation
import Testing
@testable import Domain

/// Same cases as the web's `upcomingPayments` suite (`tests/domain/upcoming-payments.test.ts`).
@Suite("Upcoming payments")
struct UpcomingPaymentsTests {
    private let calendar = Fixtures.calendar
    private let now = Fixtures.date(2026, 11, 12, hour: 15)
    private let loanID = UUID()
    private let bank = UUID()

    private func compute(
        transactions: [Transaction] = [],
        rules: [RecurringRule] = [],
        accounts: [Account] = [],
        loans: [Loan] = [],
        debts: [PersonalDebt] = [],
        on date: Date? = nil,
        days: Int,
    ) -> [UpcomingPayment] {
        UpcomingPayments.compute(
            UpcomingPayments.Ledger(transactions: transactions, rules: rules, accounts: accounts, loans: loans, personalDebts: debts),
            on: date ?? now,
            days: days,
            calendar: calendar,
        )
    }

    private func loan(frequency: LoanFrequency = .monthly, count: Int = 12, first: Date) -> Loan {
        Loan(
            id: loanID, name: "Motorbike", borrowed: Money(1200, "USD"), installmentAmount: 100,
            installmentCount: count, frequency: frequency, firstDueDate: first,
        )
    }

    private func rule(start: Date, next: Date, end: Date? = nil, paused: Bool = false) -> RecurringRule {
        RecurringRule(
            name: "Gym", kind: .expense, categoryID: nil, amount: 25, currency: "USD", accountID: bank,
            frequency: .monthly, startDate: start, nextDate: next, endDate: end, isPaused: paused,
        )
    }

    @Test
    func everyOverdueInstallmentHasItsOwnRowAndDays() {
        let payments = compute(loans: [loan(first: Fixtures.date(2026, 9, 10, hour: 0))], days: 0)
        let id = loanID.uuidString.lowercased()
        #expect(payments.map(\.id) == ["installment:\(id):1", "installment:\(id):2", "installment:\(id):3"])
        #expect(payments.map(\.daysFromToday) == [-63, -33, -2])
        #expect(payments.allSatisfy { $0.status == .overdue })
        #expect(payments.first?.kind == .installment(loanID: loanID, number: 1, count: 12))
        #expect(payments.first?.amount == Money(100, "USD"))
    }

    @Test
    func aWeeklyLoanHasSeveralInstallmentsInTheWindow() {
        let weekly = loan(frequency: .weekly, count: 4, first: Fixtures.date(2026, 11, 13, hour: 0))
        #expect(compute(loans: [weekly], days: 14).count == 2)
    }

    @Test
    func aDraftDatedAheadIsUpcomingAndNoneAfterTheWindow() {
        let ahead = Fixtures.transaction(amount: "10", status: .planned, date: Fixtures.date(2026, 11, 15))
        let far = Fixtures.transaction(amount: "10", status: .planned, date: Fixtures.date(2026, 11, 30))
        let payments = compute(transactions: [ahead, far], days: 7)
        #expect(payments.map(\.id) == ["draft:\(ahead.id.uuidString.lowercased())"])
        #expect(payments.map(\.status) == [.upcoming])
    }

    @Test
    func todaysOccurrenceIsTodayAndEndedOrPausedRulesHaveNone() {
        let start = Fixtures.date(2026, 1, 12)
        let today = Fixtures.date(2026, 11, 12)
        let active = rule(start: start, next: today)
        let ended = rule(start: start, next: today, end: Fixtures.date(2026, 11, 1))
        let paused = rule(start: start, next: today, paused: true)
        let payments = compute(rules: [active, ended, paused], days: 3)
        #expect(payments.map(\.id) == ["recurring:\(active.id.uuidString.lowercased()):2026-11-12"])
        #expect(payments.map(\.status) == [.today])
    }

    @Test
    func aCardWithNothingToPayIsLeftOut() throws {
        let terms = { (day: Int) throws(DomainError) in try CreditTerms(debtMode: .principal, dueDay: day) }
        let owes = try Account(
            name: "Visa", kind: .credit, openingBalances: [Money(0, "USD")], openingDate: Fixtures.date(2026, 1, 1),
            creditTerms: terms(14),
        )
        let paid = try Account(
            name: "Amex", kind: .credit, openingBalances: [Money(0, "USD")], openingDate: Fixtures.date(2026, 1, 1),
            creditTerms: terms(13),
        )
        let charge = Fixtures.transaction(amount: "80", account: owes.id, date: Fixtures.date(2026, 11, 2), rate: .single("USD"))
        let payments = compute(transactions: [charge], accounts: [owes, paid], days: 7)
        #expect(payments.map(\.id) == ["card:\(owes.id.uuidString.lowercased()):2026-11-14"])
        #expect(payments.first?.amount == Money(80, "USD"))
    }

    @Test
    func listsAnOpenDebtWithADueDateEitherDirectionForWhatIsLeftInItsCurrency() throws {
        let debt = { (id: String, direction: DebtDirection, due: Date?, repaid: Decimal?, settled: Date?) throws in
            try PersonalDebt(
                id: #require(UUID(uuidString: "00000000-0000-4000-8000-0000000000\(id)")),
                person: direction == .iOwe ? "Luis" : "Ana",
                direction: direction,
                amount: Money(100, "NIO"),
                date: Fixtures.date(2026, 10, 1),
                repayments: repaid.map { [DebtRepayment(amount: $0, date: Fixtures.date(2026, 10, 20))] } ?? [],
                settledAt: settled,
                dueDate: due,
            )
        }
        let late = try debt("d1", .theyOweMe, Fixtures.date(2026, 11, 9, hour: 0), 30, nil)
        let mine = try debt("d2", .iOwe, Fixtures.date(2026, 11, 14, hour: 0), nil, nil)
        let undated = try debt("d3", .theyOweMe, nil, nil, nil)
        let settled = try debt("d4", .theyOweMe, Fixtures.date(2026, 11, 10, hour: 0), nil, Fixtures.date(2026, 11, 10))
        let far = try debt("d5", .theyOweMe, Fixtures.date(2026, 11, 30, hour: 0), nil, nil)
        let payments = compute(debts: [far, settled, undated, mine, late], days: 7)
        #expect(payments.map(\.id) == ["debt:\(late.id.uuidString.lowercased())", "debt:\(mine.id.uuidString.lowercased())"])
        #expect(payments.map(\.status) == [.overdue, .upcoming])
        #expect(payments.map(\.daysFromToday) == [-3, 2])
        #expect(payments.first?.kind == .debt(debtID: late.id, person: "Ana", direction: .theyOweMe))
        #expect(payments.first?.amount == Money(70, "NIO"))
        #expect(payments.last?.kind == .debt(debtID: mine.id, person: "Luis", direction: .iOwe))
    }

    @Test
    func leavesOutAClosedAccountsCardEvenOwingAndItsRulesFromOrToIt() throws {
        let closedAt = Fixtures.date(2026, 11, 1)
        let id = { (suffix: String) throws in try #require(UUID(uuidString: "00000000-0000-4000-8000-0000000000\(suffix)")) }
        let card = try Account(
            id: id("b8"), name: "Visa", kind: .credit, openingBalances: [Money(0, "USD")],
            openingDate: Fixtures.date(2026, 1, 1), creditTerms: CreditTerms(debtMode: .principal, dueDay: 14), closedAt: closedAt,
        )
        let savings = try Account(
            id: id("b9"), name: "Old", kind: .deposit, openingBalances: [Money(0, "USD")],
            openingDate: Fixtures.date(2026, 1, 1), closedAt: closedAt,
        )
        let charge = Fixtures.transaction(amount: "80", account: card.id, date: Fixtures.date(2026, 11, 2), rate: .single("USD"))
        let today = Fixtures.date(2026, 11, 12)
        let rule = { (suffix: String, account: UUID, destination: UUID?) throws in
            try RecurringRule(
                id: id(suffix), name: "Gym", kind: destination == nil ? .expense : .transfer, categoryID: nil, amount: 25,
                currency: "USD", accountID: account, destinationAccountID: destination, frequency: .monthly,
                startDate: Fixtures.date(2026, 1, 12), nextDate: today,
            )
        }
        let open = try rule("e3", bank, nil)
        let onCard = try rule("e4", card.id, nil)
        let intoClosed = try rule("e5", bank, savings.id)
        let rules = [onCard, intoClosed, open]
        let key = { (rule: RecurringRule) in "recurring:\(rule.id.uuidString.lowercased()):2026-11-12" }
        let payments = compute(transactions: [charge], rules: rules, accounts: [card, savings], days: 7)
        #expect(payments.map(\.id) == [key(open)])
        // Reopened, both come back.
        let reopened = compute(
            transactions: [charge],
            rules: rules,
            accounts: [card.with(closedAt: nil), savings.with(closedAt: nil)],
            days: 7,
        )
        #expect(reopened.map(\.id) == [key(open), key(onCard), key(intoClosed), "card:\(card.id.uuidString.lowercased()):2026-11-14"])
    }

    @Test
    func ordersByDayThenKindThenIDBytes() {
        let day = now
        let draft = Fixtures.transaction(amount: "1", status: .planned, date: day)
        let item = { (id: String, kind: UpcomingPayment.Kind, days: Int) in
            UpcomingPayment(id: id, kind: kind, date: day, amount: Money(1, "USD"), daysFromToday: days)
        }
        let recurring = UpcomingPayment.Kind.recurring(rule(start: day, next: day))
        let sorted = [
            item("recurring:b", recurring, 0),
            item("debt:a", .debt(debtID: UUID(), person: "Ana", direction: .iOwe), 0),
            item("card:a", .card(accountID: bank, dueDay: 1), 0),
            item("draft:b", .draft(draft), 0),
            item("draft:B", .draft(draft), 0),
            item("installment:a", .installment(loanID: loanID, number: 1, count: 1), 0),
            item("recurring:a", recurring, -1),
        ].sorted(by: UpcomingPayment.precedes)
        #expect(sorted.map(\.id) == ["recurring:a", "draft:B", "draft:b", "installment:a", "card:a", "recurring:b", "debt:a"])
    }

    @Test
    func countsCalendarDaysInTheCalendarsZone() {
        // 11pm in Managua on the 12th is already the 13th in UTC: today stays the 12th.
        let late = Fixtures.date(2026, 11, 12, hour: 23)
        let gym = rule(start: Fixtures.date(2026, 1, 13), next: Fixtures.date(2026, 11, 13))
        let payments = compute(rules: [gym], on: late, days: 1)
        #expect(payments.map(\.daysFromToday) == [1])
        #expect(payments.map(\.status) == [.upcoming])
    }
}
