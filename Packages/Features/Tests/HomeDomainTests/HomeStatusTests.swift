import Domain
import DomainSamples
import Foundation
import Testing
@testable import HomeDomain

/// The line under home's greeting comes from the same notifications and loans that home's lists
/// show, the same cases as keepwell-web's `tests/home-status.test.ts`.
@Suite("Home status")
struct HomeStatusTests {
    private let calendar = Calendar.current

    private func date(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)) ?? .now
    }

    private func overview(now: Date) async throws -> HomeOverview {
        let store = InMemoryStore(sample: .standard)
        return try await DefaultGetHomeOverviewUseCase(
            accounts: store, cards: store, transactions: store, categories: store, settings: store,
            recurringRules: store, loans: store, calendar: calendar, now: { now },
        ).execute()
    }

    @Test
    func countsExactlyTheDraftsHomeListsAsLateFromTheSameNotifications() async throws {
        // The sample's drafts are on Oct 24, 25 and 28: on the 26th, two are late and one is ahead.
        let now = date(10, 26)
        let overview = try await overview(now: now)
        let today = calendar.startOfDay(for: now)
        let late = overview.planned.filter { calendar.startOfDay(for: $0.date) <= today }
        let status = HomeStatus(on: now, in: overview, calendar: calendar)
        #expect(late.count == 2)
        #expect(status.toConfirm == late.count)
        #expect(status.toConfirm == LedgerNotifications.applying(on: now, in: overview, calendar: calendar).count { $0.kind == .planned })
        #expect(!status.isClear)
    }

    @Test
    func anOverdueInstallmentIsNeverAllCaughtUp() async throws {
        // The motorbike's third installment was due Oct 28; the debts card marks it overdue.
        let now = date(11, 2)
        let overview = try await overview(now: now)
        let status = HomeStatus(on: now, in: overview, calendar: calendar)
        #expect(status.overdue == overview.loans.count(where: \.isNextOverdue))
        #expect(status.overdue == 1)
        #expect(!status.isClear)
    }

    @Test
    func nothingPendingIsClear() {
        #expect(HomeStatus(notifications: [], loans: []).isClear)
        #expect(HomeStatus(notifications: [], loans: []) == HomeStatus())
    }

    @Test
    func sortsPaymentsInstallmentsAndRenewalsByTheDayTheyAreDue() {
        let day = date(10, 26)
        let account = UUID()
        let notification = { (id: String, subject: LedgerNotification.Subject) in
            LedgerNotification(id: id, subject: subject, date: day, target: .debts)
        }
        let status = HomeStatus(
            notifications: [
                notification("a", .payment(accountID: account, dueDay: 26, due: day, daysLeft: 0)),
                notification("b", .installment(loanID: UUID(), number: 1, daysLeft: 1)),
                notification("c", .payment(accountID: account, dueDay: 29, due: day, daysLeft: 3)),
                notification("d", .cutoff(accountID: account)),
            ],
            loans: [],
        )
        #expect(status == HomeStatus(dueToday: 1, dueTomorrow: 1))
    }
}
