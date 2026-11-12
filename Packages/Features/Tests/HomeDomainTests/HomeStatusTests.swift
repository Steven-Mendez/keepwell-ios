import Domain
import DomainSamples
import Foundation
import Testing
@testable import HomeDomain

/// The line under home's greeting comes from the same list as home's "Upcoming" card, the same
/// cases as keepwell-web's `tests/home-status.test.ts`.
@Suite("Home status")
struct HomeStatusTests {
    private let calendar = Calendar.current

    private func date(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)) ?? .now
    }

    private func overview(now: Date, store: InMemoryStore = InMemoryStore(sample: .standard)) async throws -> HomeOverview {
        try await DefaultGetHomeOverviewUseCase(
            accounts: store, cards: store, transactions: store, categories: store, settings: store,
            recurringRules: store, loans: store, calendar: calendar, now: { now },
        ).execute()
    }

    @Test
    func countsExactlyTheDraftsTheUpcomingCardListsAsLateOrForToday() async throws {
        // The sample's drafts are on Oct 24, 25 and 28: on the 26th, two are late and one is ahead.
        let now = date(10, 26)
        let overview = try await overview(now: now)
        let today = calendar.startOfDay(for: now)
        let late = overview.planned.filter { calendar.startOfDay(for: $0.date) <= today }
        let status = HomeStatus(overview)
        #expect(late.count == 2)
        #expect(status.toConfirm == late.count)
        let listed = overview.upcomingPayments.filter {
            if case .draft = $0.kind {
                $0.status != .upcoming
            } else {
                false
            }
        }
        #expect(status.toConfirm == listed.count)
        #expect(status.toConfirm == LedgerNotifications.applying(on: now, in: overview, calendar: calendar).count { $0.kind == .planned })
        #expect(!status.isClear)
    }

    @Test
    func anOverdueInstallmentIsNeverAllCaughtUp() async throws {
        // The motorbike's third installment was due Oct 28; the card lists it as overdue.
        let now = date(11, 2)
        let overview = try await overview(now: now)
        let status = HomeStatus(overview)
        let overdue = overview.upcomingPayments.filter {
            if case .installment = $0.kind {
                $0.status == .overdue
            } else {
                false
            }
        }
        #expect(status.overdue == overdue.count)
        #expect(status.overdue == 1)
        #expect(!status.isClear)
    }

    @Test
    func todayAndTomorrowMatchTheReminders() async throws {
        // Every day of a month: cards that owe something and installments count the same as the
        // payment and installment reminders, and renewals and bills as theirs. Loans are kept up to
        // date: the reminders skip a loan whose next installment is late, the list doesn't.
        let store = InMemoryStore(sample: .standard)
        for loan in await store.fetchLoans() {
            let late = LoanProgress(loan: loan, today: date(11, 1), calendar: calendar).installments
                .filter { !$0.isPaid && $0.dueDate < date(11, 1) }
                .map { LoanPayment(number: $0.number, paidAt: $0.dueDate) }
            await store.save(Loan(
                id: loan.id, name: loan.name, lender: loan.lender, borrowed: loan.borrowed, installmentAmount: loan.installmentAmount,
                installmentCount: loan.installmentCount, frequency: loan.frequency, firstDueDate: loan.firstDueDate,
                payments: loan.payments + late,
            ))
        }
        for day in 1 ... 30 {
            let now = date(11, day)
            let overview = try await overview(now: now, store: store)
            let reminders = LedgerNotifications.applying(on: now, in: overview, calendar: calendar)
            var expected = HomeStatus()
            for notification in reminders {
                switch notification.subject {
                case let .payment(accountID, _, _, daysLeft):
                    // A card with nothing to pay still gets its reminder but isn't pending.
                    let owes = overview.upcomingPayments.contains {
                        if case let .card(id, _) = $0.kind {
                            id == accountID
                        } else {
                            false
                        }
                    }
                    if owes, daysLeft == 0 {
                        expected.dueToday += 1
                    }
                    if owes, daysLeft == 1 {
                        expected.dueTomorrow += 1
                    }
                case let .installment(_, _, daysLeft):
                    if daysLeft == 0 {
                        expected.dueToday += 1
                    }
                    if daysLeft == 1 {
                        expected.dueTomorrow += 1
                    }
                case .renewal, .bill:
                    expected.dueTomorrow += 1
                default:
                    break
                }
            }
            let status = HomeStatus(overview)
            #expect(status.dueToday == expected.dueToday, "Nov \(day)")
            #expect(status.dueTomorrow == expected.dueTomorrow, "Nov \(day)")
        }
    }

    @Test
    func nothingPendingIsClear() {
        #expect(HomeStatus(payments: []).isClear)
        #expect(HomeStatus(payments: []) == HomeStatus())
    }

    @Test
    func countsCardsInstallmentsRenewalsAndBillsByTheDayTheyAreDue() {
        let day = date(10, 26)
        let account = UUID()
        let rule = { (subscription: Bool, kind: TransactionKind, auto: Bool) in
            RecurringRule(
                name: "R", kind: kind, categoryID: nil, amount: 1, currency: "USD", accountID: account,
                frequency: .monthly, startDate: day, isSubscription: subscription, autoConfirm: auto,
            )
        }
        let payment = { (id: String, kind: UpcomingPayment.Kind, days: Int) in
            UpcomingPayment(id: id, kind: kind, date: day, amount: Money(1, "USD"), daysFromToday: days)
        }
        let draft = Transaction(
            date: day, status: .planned, description: "D", kind: .expense, categoryID: nil, amount: 1, currency: "USD",
            accountID: account, exchangeRate: .single("USD"),
        )
        let status = HomeStatus(payments: [
            payment("a", .card(accountID: account, dueDay: 26), 0),
            payment("b", .installment(loanID: UUID(), number: 1, count: 2), 1),
            payment("c", .card(accountID: account, dueDay: 29), 3),
            payment("d", .installment(loanID: UUID(), number: 1, count: 2), -2),
            payment("e", .draft(draft), -1),
            payment("f", .draft(draft), 0),
            payment("g", .draft(draft), 2),
            payment("h", .recurring(rule(true, .expense, true)), 1),
            payment("i", .recurring(rule(false, .expense, false)), 1),
            payment("j", .recurring(rule(false, .expense, true)), 1),
            payment("k", .recurring(rule(false, .income, false)), 1),
            payment("l", .recurring(rule(true, .expense, false)), 2),
        ])
        #expect(status == HomeStatus(toConfirm: 2, overdue: 1, dueToday: 1, dueTomorrow: 3))
    }
}
