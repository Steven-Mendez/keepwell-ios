import Domain
import DomainSamples
import Foundation
import Testing
@testable import HomeDomain

/// The "debt" kind, the same cases as keepwell-web's `tests/notifications.test.ts`: a personal debt
/// due inside the card payment window, in either direction, and never once it is overdue.
@Suite("Personal debt notifications")
struct DebtNotificationsTests {
    private let calendar = Calendar.current
    private let debtID = UUID(uuidString: "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD") ?? UUID()

    private func date(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)) ?? .now
    }

    private func debt(
        due: Date?,
        direction: DebtDirection = .theyOweMe,
        repaid: Decimal? = nil,
        settledAt: Date? = nil,
    ) -> PersonalDebt {
        PersonalDebt(
            id: debtID,
            person: "Ana",
            direction: direction,
            amount: Money(12, "USD"),
            date: date(9, 1),
            repayments: repaid.map { [DebtRepayment(amount: $0, date: date(11, 12))] } ?? [],
            settledAt: settledAt,
            dueDate: due,
        )
    }

    private func found(_ debts: [PersonalDebt], now: Date) async throws -> [LedgerNotification] {
        let store = InMemoryStore(sample: .standard)
        for debt in debts {
            await store.save(debt)
        }
        let overview = try await DefaultGetHomeOverviewUseCase(
            accounts: store, cards: store, transactions: store, categories: store, settings: store,
            recurringRules: store, personalDebts: store, calendar: calendar, now: { now },
        ).execute()
        return LedgerNotifications.applying(on: now, in: overview, calendar: calendar).filter { $0.kind == .debt }
    }

    @Test
    func aDebtDueInsideTheWindowIsRemindedFromItsFirstDay() async throws {
        // The sample reminds three days before.
        let now = date(11, 12)
        let notifications = try await found([debt(due: date(11, 15, hour: 0))], now: now)
        let notification = try #require(notifications.first)
        #expect(notifications.count == 1)
        #expect(notification.id == "debt:dddddddd-dddd-4ddd-8ddd-dddddddddddd:2026-11-15")
        // A target every published app already decodes, so an older one still opens a pushed one.
        #expect(notification.target == .debts)
        #expect(notification.date == calendar.startOfDay(for: now))
        guard case let .debt(subject, _, daysLeft) = notification.subject else {
            Issue.record("Not a debt")
            return
        }
        #expect(subject.id == debtID)
        #expect(daysLeft == 3)
    }

    @Test
    func fourDaysAheadOverdueSettledOrWithoutADateGiveNothing() async throws {
        let now = date(11, 12)
        #expect(try await found([debt(due: date(11, 16, hour: 0))], now: now).isEmpty)
        #expect(try await found([debt(due: date(11, 11, hour: 0))], now: now).isEmpty)
        #expect(try await found([debt(due: date(11, 15, hour: 0), settledAt: now)], now: now).isEmpty)
        #expect(try await found([debt(due: nil)], now: now).isEmpty)
    }

    @Test
    func aRepaymentKeepsTheIdAndBothDirectionsAreReminded() async throws {
        let now = date(11, 12)
        let ids = try await found([debt(due: date(11, 15, hour: 0), repaid: 5)], now: now).map(\.id)
        #expect(ids == ["debt:dddddddd-dddd-4ddd-8ddd-dddddddddddd:2026-11-15"])
        #expect(try await found([debt(due: date(11, 15, hour: 0), direction: .iOwe)], now: now).count == 1)
    }
}
