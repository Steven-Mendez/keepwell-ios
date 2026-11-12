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
            recurringRules: store, loans: store, personalDebts: store, calendar: calendar, now: { now },
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
        // One debt each way, due on the 12th and the 13th: before, reminded like an installment;
        // after, overdue, which neither the reminders nor today and tomorrow count.
        for (person, direction, day) in [("Ana", DebtDirection.theyOweMe, 12), ("Luis", .iOwe, 13)] {
            await store.save(PersonalDebt(
                person: person, direction: direction, amount: Money(20, "USD"), date: date(10, 1),
                dueDate: calendar.startOfDay(for: date(11, day)),
            ))
        }
        for day in 1 ... 30 {
            let now = date(11, day)
            let overview = try await overview(now: now, store: store)
            let reminders = LedgerNotifications.applying(on: now, in: overview, calendar: calendar)
            let expected = Self.dueSoon(reminders, listing: overview.upcomingPayments)
            let status = HomeStatus(overview)
            #expect(status.dueToday == expected.dueToday, "Nov \(day)")
            #expect(status.dueTomorrow == expected.dueTomorrow, "Nov \(day)")
            #expect(status.overdueDebts == (day > 12 ? 1 : 0) + (day > 13 ? 1 : 0), "Nov \(day)")
        }
    }

    /// Today and tomorrow as the reminders count them. A card with nothing to pay still gets its
    /// reminder but isn't pending, so it counts only when `payments` lists it.
    private static func dueSoon(_ reminders: [LedgerNotification], listing payments: [UpcomingPayment]) -> HomeStatus {
        var expected = HomeStatus()
        for notification in reminders {
            switch notification.subject {
            case let .payment(accountID, _, _, daysLeft):
                let owes = payments.contains {
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
            case let .installment(_, _, daysLeft), let .debt(_, _, daysLeft):
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
        return expected
    }

    @Test
    func countsPersonalDebtsAsUpcomingListsThemNeverAllCaughtUpWhileOneIsLate() async throws {
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 15)) ?? .now
        let debt = { (direction: DebtDirection, due: Int?, settled: Bool) in
            PersonalDebt(
                person: "Ana", direction: direction, amount: Money(50, "USD"), date: date(10, 1),
                settledAt: settled ? date(11, 2) : nil,
                dueDate: due.map { calendar.startOfDay(for: date(11, $0)) },
            )
        }
        let owedLate = debt(.theyOweMe, 5, false)
        let oweLate = debt(.iOwe, 10, false)
        let today = debt(.iOwe, 12, false)
        let tomorrow = debt(.theyOweMe, 13, false)
        let settled = debt(.theyOweMe, 1, true)
        let undated = debt(.iOwe, nil, false)

        // One late debt, whichever way it goes, is enough to drop "All caught up".
        for late in [owedLate, oweLate] {
            let overview = try await overview(now: now, store: InMemoryStore(personalDebts: [late, settled, undated]))
            #expect(overview.upcomingPayments.map(\.status) == [.overdue])
            #expect(overview.upcomingPayments.map(\.id) == ["debt:\(late.id.uuidString.lowercased())"])
            #expect(HomeStatus(overview) == HomeStatus(overdueDebts: 1))
        }
        #expect(try await HomeStatus(overview(now: now, store: InMemoryStore(personalDebts: [settled, undated]))).isClear)

        let store = InMemoryStore(personalDebts: [owedLate, oweLate, today, tomorrow, settled, undated])
        let overview = try await overview(now: now, store: store)
        let status = HomeStatus(overview)
        #expect(status == HomeStatus(overdueDebts: 2, dueToday: 1, dueTomorrow: 1))
        let listedLate = overview.upcomingPayments.count {
            if case .debt = $0.kind {
                $0.status == .overdue
            } else {
                false
            }
        }
        #expect(status.overdueDebts == listedLate)
    }

    @Test
    func nothingPendingIsClear() {
        #expect(HomeStatus(payments: []).isClear)
        #expect(HomeStatus(payments: []) == HomeStatus())
    }

    @Test
    func countsCardsInstallmentsDebtsRenewalsAndBillsByTheDayTheyAreDue() {
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
            payment("m", .debt(debtID: UUID(), person: "Ana", direction: .theyOweMe), -3),
            payment("n", .debt(debtID: UUID(), person: "Luis", direction: .iOwe), 0),
            payment("o", .debt(debtID: UUID(), person: "Ana", direction: .iOwe), 1),
            payment("p", .debt(debtID: UUID(), person: "Ana", direction: .theyOweMe), 2),
        ])
        #expect(status == HomeStatus(toConfirm: 2, overdue: 1, overdueDebts: 1, dueToday: 2, dueTomorrow: 4))
    }
}
