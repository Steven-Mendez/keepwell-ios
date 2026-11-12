import Domain
import DomainSamples
import Foundation
import Testing
@testable import HomeDomain
@testable import HomePresentation

/// How a personal debt's reminder reads (keepwell-web `notification-copy.ts`, the API's push).
@MainActor
@Suite("Home debt reminders")
struct HomeDebtReminderTests {
    private let now = SampleData.defaultReferenceDate

    private func reminder(_ debt: PersonalDebt) async throws -> Reminder {
        let store = InMemoryStore(sample: .standard)
        await store.save(debt)
        let viewModel = HomeViewModel(
            getOverview: DefaultGetHomeOverviewUseCase(
                accounts: store, cards: store, transactions: store, categories: store, settings: store,
                recurringRules: store, personalDebts: store, now: { [now] in now },
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store),
            getPreferredName: DefaultGetPreferredNameUseCase(profile: InMemoryPasscodeStore()),
        )
        await viewModel.load()
        let earlier = Calendar.current.startOfDay(for: now).addingTimeInterval(-60)
        return try #require(viewModel.reminders(now: earlier).first { $0.kind == .debt })
    }

    private func debt(daysAhead: Int, direction: DebtDirection) -> PersonalDebt {
        let calendar = Calendar.current
        let due = calendar.date(byAdding: .day, value: daysAhead, to: calendar.startOfDay(for: now)) ?? now
        return PersonalDebt(
            person: "Ana", direction: direction, amount: Money(12, "USD"),
            date: calendar.date(byAdding: .month, value: -2, to: now) ?? now,
            repayments: [DebtRepayment(amount: 5, date: now)], dueDate: due,
        )
    }

    @Test
    func saysWhoWhenAndWhatIsLeftInTheDebtsDirection() async throws {
        let owed = try await reminder(debt(daysAhead: 3, direction: .theyOweMe))
        #expect(owed.title == "Ana: due in 3 days")
        #expect(owed.body == "They owe you $7.00.")
        #expect(owed.target == ["screen": "debts"])
        let owing = try await reminder(debt(daysAhead: 0, direction: .iOwe))
        #expect(owing.title == "Ana: due today")
        #expect(owing.body == "You owe $7.00.")
    }
}
