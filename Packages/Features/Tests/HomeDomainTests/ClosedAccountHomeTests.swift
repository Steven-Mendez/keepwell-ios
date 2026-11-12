import Domain
import DomainSamples
import Foundation
import Testing
@testable import HomeDomain

/// A closed account on Home (T25): no card reminders, out of the accounts and counts, still in the totals.
@Suite("Closed account on Home")
struct ClosedAccountHomeTests {
    private let calendar = Calendar.current

    private func date(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)) ?? .now
    }

    private func overview(_ store: InMemoryStore, now: Date) async throws -> HomeOverview {
        try await DefaultGetHomeOverviewUseCase(
            accounts: store, cards: store, transactions: store, categories: store, settings: store,
            recurringRules: store, loans: store, calendar: calendar, now: { now },
        ).execute()
    }

    private func closing(_ id: UUID, in store: InMemoryStore) async throws {
        let account = try #require(await store.fetchAccounts().first { $0.id == id })
        await store.save(account.with(closedAt: date(10, 1)))
    }

    @Test
    func aClosedCardHasNoPaymentOrCutoffReminder() async throws {
        let store = InMemoryStore(sample: .standard)
        // The sample's Visa is due on the 15th and closes on the 28th.
        let kinds = { (now: Date) async throws -> [LedgerNotification.Kind] in
            try await LedgerNotifications.applying(on: now, in: overview(store, now: now), calendar: calendar).map(\.kind)
        }
        #expect(try await kinds(date(11, 13)).contains(.payment))
        #expect(try await kinds(date(10, 28)).contains(.cutoff))
        try await closing(SampleData.IDs.visa, in: store)
        #expect(try await !kinds(date(11, 13)).contains(.payment))
        #expect(try await !kinds(date(10, 28)).contains(.cutoff))
    }

    @Test
    func aClosedAccountLeavesTheListAndCountsNotTheTotals() async throws {
        let store = InMemoryStore(sample: .standard)
        let now = date(10, 22)
        let before = try await overview(store, now: now)
        try await closing(SampleData.IDs.savings, in: store)
        let after = try await overview(store, now: now)
        #expect(!after.balances.contains { $0.account.id == SampleData.IDs.savings })
        #expect(after.accountCount == before.accountCount - 1)
        #expect(after.cardCount == before.cardCount - 1)
        #expect(after.netWorth == before.netWorth)
    }
}
