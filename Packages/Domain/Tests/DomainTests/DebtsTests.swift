import Foundation
import Testing
@testable import Domain

@Suite("Loans and personal debts")
struct DebtsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Managua") ?? .gmt
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
    }

    private func loan(
        name: String = "Motorbike",
        count: Int = 12,
        frequency: LoanFrequency = .monthly,
        first: Date? = nil,
        paid: [Int] = [],
    ) -> Loan {
        Loan(
            name: name,
            borrowed: Money(20000, "NIO"),
            installmentAmount: Decimal(string: "1916.67") ?? 0,
            installmentCount: count,
            frequency: frequency,
            firstDueDate: first ?? date(2026, 1, 31),
            payments: paid.map { LoanPayment(number: $0, paidAt: date(2026, 1, $0)) },
        )
    }

    @Test
    func monthlyInstallmentsKeepTheirDayAndClampToShortMonths() {
        let progress = LoanProgress(loan: loan(count: 4), today: date(2026, 1, 1), calendar: calendar)
        let days = progress.installments.map { calendar.dateComponents([.month, .day], from: $0.dueDate) }
        #expect(days.map(\.month) == [1, 2, 3, 4])
        #expect(days.map(\.day) == [31, 28, 31, 30])
    }

    @Test
    func weeklyInstallmentsAreSevenDaysApart() {
        let progress = LoanProgress(
            loan: loan(count: 3, frequency: .weekly, first: date(2026, 11, 2)),
            today: date(2026, 11, 1),
            calendar: calendar,
        )
        #expect(progress.installments.map(\.dueDate) == [date(2026, 11, 2), date(2026, 11, 9), date(2026, 11, 16)])
    }

    @Test
    func whatIsLeftCountsTheUnpaidInstallments() {
        let progress = LoanProgress(loan: loan(paid: [1, 2]), today: date(2026, 2, 1), calendar: calendar)
        #expect(progress.remaining == Decimal(string: "19166.70"))
        #expect(progress.totalToPay == Decimal(string: "23000.04"))
        #expect(progress.next?.number == 3)
        #expect(!progress.isNextOverdue)
        let late = LoanProgress(loan: loan(paid: [1, 2]), today: date(2026, 4, 1), calendar: calendar)
        #expect(late.isNextOverdue)
    }

    @Test
    func payingMarksTheNextInstallmentUntilPaidOff() throws {
        let id = UUID()
        var current = loan(count: 2, paid: [1])
        current = try current.paying(at: date(2026, 2, 27), transactionID: id)
        #expect(current.payments.last == LoanPayment(number: 2, paidAt: date(2026, 2, 27), transactionID: id))
        #expect(current.isPaidOff)
        #expect(current.nextNumber == nil)
        #expect(throws: DomainError.invalidAmount) { try current.paying(at: .now, transactionID: nil) }
    }

    @Test
    func aLoanNeedsPositiveAmountsAndDistinctPaymentsInTheSchedule() {
        #expect(throws: DomainError.invalidAmount) {
            try Loan(name: "X", borrowed: Money(0, "NIO"), installmentAmount: 1, installmentCount: 1, firstDueDate: .now).check()
        }
        #expect(throws: DomainError.invalidAmount) {
            try Loan(name: "X", borrowed: Money(1, "NIO"), installmentAmount: 1, installmentCount: 601, firstDueDate: .now).check()
        }
        #expect(throws: DomainError.self) { try loan(count: 2, paid: [1, 1]).check() }
        #expect(throws: DomainError.self) { try loan(count: 2, paid: [3]).check() }
    }

    @Test
    func loansOrderBySoonestNextInstallmentThenPaidOffLast() {
        let ordered = LoanProgress.ordered(
            [
                loan(name: "Done", count: 1, paid: [1]),
                loan(name: "Later", first: date(2026, 3, 1)),
                loan(name: "Soon", first: date(2026, 2, 1)),
            ],
            today: date(2026, 1, 15),
            calendar: calendar,
        )
        #expect(ordered.map(\.loan.name) == ["Soon", "Later", "Done"])
    }

    @Test
    func repayingToTheEndSettlesTheDebt() throws {
        let debt = PersonalDebt(person: "Juan", direction: .theyOweMe, amount: Money(500, "NIO"), date: date(2026, 11, 1))
        let partial = try debt.repaying(200, on: date(2026, 11, 2))
        #expect(partial.remaining == 300)
        #expect(!partial.isSettled)
        #expect(throws: DomainError.invalidAmount) { try partial.repaying(Decimal(string: "300.01") ?? 0, on: .now) }
        #expect(throws: DomainError.invalidAmount) { try partial.repaying(0, on: .now) }
        let paid = try partial.repaying(300, on: date(2026, 11, 5))
        #expect(paid.remaining == 0)
        #expect(paid.settledAt == date(2026, 11, 5))
        #expect(throws: DomainError.invalidAmount) { try paid.reopened() }
    }

    @Test
    func settlingByHandKeepsWhatWasLeftAndCanBeReopened() throws {
        let debt = PersonalDebt(person: "Ana", direction: .iOwe, amount: Money(40, "USD"), date: date(2026, 11, 1))
        let settled = debt.settled(at: date(2026, 11, 3))
        #expect(settled.isSettled)
        #expect(settled.remaining == 40)
        #expect(try !settled.reopened().isSettled)
    }

    @Test
    func totalsArePerCurrencyAndSkipWhatIsClosed() {
        let debts = [
            PersonalDebt(
                person: "Juan",
                direction: .theyOweMe,
                amount: Money(500, "NIO"),
                date: .now,
                repayments: [DebtRepayment(amount: 200, date: .now)],
            ),
            PersonalDebt(person: "Luis", direction: .theyOweMe, amount: Money(20, "USD"), date: .now),
            PersonalDebt(person: "Ana", direction: .iOwe, amount: Money(40, "USD"), date: .now),
            PersonalDebt(person: "Old", direction: .iOwe, amount: Money(99, "USD"), date: .now, settledAt: .now),
        ]
        let totals = DebtTotals(loans: [loan(paid: [1, 2]), loan(count: 1, paid: [1])], debts: debts)
        #expect(totals.owedToYou == [Money(300, "NIO"), Money(20, "USD")])
        #expect(totals.youOwe == [Money(Decimal(string: "19166.70") ?? 0, "NIO"), Money(40, "USD")])
    }

    @Test
    func openDebtsComeFirstNewestFirst() {
        let ordered = PersonalDebtOrder.ordered([
            PersonalDebt(person: "Old", direction: .iOwe, amount: Money(1, "USD"), date: date(2026, 10, 1)),
            PersonalDebt(person: "Settled", direction: .iOwe, amount: Money(1, "USD"), date: date(2026, 11, 3), settledAt: .now),
            PersonalDebt(person: "New", direction: .theyOweMe, amount: Money(1, "USD"), date: date(2026, 11, 2)),
        ])
        #expect(ordered.map(\.person) == ["New", "Old", "Settled"])
    }

    @Test
    func anEqualSplitCountsThePersonAndRoundsDown() throws {
        #expect(BillSplit.equalShare(of: 900, people: 2) == 300)
        #expect(BillSplit.equalShare(of: 100, people: 2) == Decimal(string: "33.33"))
        #expect(BillSplit.equalShare(of: 100, people: 0) == 0)
        try BillSplit.check([50, 50], total: 100)
        #expect(throws: DomainError.invalidAmount) { try BillSplit.check([60, 41], total: 100) }
        #expect(throws: DomainError.invalidAmount) { try BillSplit.check([0], total: 100) }
        #expect(throws: DomainError.invalidAmount) { try BillSplit.check([], total: 100) }
    }
}
