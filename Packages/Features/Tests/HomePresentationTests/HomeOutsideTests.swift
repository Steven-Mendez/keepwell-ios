import Domain
import DomainSamples
import Foundation
import Testing
@testable import HomeDomain
@testable import HomePresentation

@MainActor
@Suite("Home widgets and reminders")
struct HomeOutsideTests {
    private let now = SampleData.defaultReferenceDate

    private func loadedViewModel() async -> HomeViewModel {
        let store = InMemoryStore(sample: .standard)
        let viewModel = HomeViewModel(
            getOverview: DefaultGetHomeOverviewUseCase(
                accounts: store, cards: store, transactions: store, categories: store, settings: store, now: { [now] in now },
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store),
            getPreferredName: DefaultGetPreferredNameUseCase(profile: InMemoryPasscodeStore()),
        )
        await viewModel.load()
        return viewModel
    }

    @Test
    func snapshotCarriesBalancesAndThreeShortcuts() async throws {
        let snapshot = try #require(await loadedViewModel().widgetSnapshot)
        #expect(snapshot.shortcuts.count == 3)
        #expect(snapshot.balances.count <= 3)
        #expect(!snapshot.netWorth.isEmpty)
        #expect((0 ... 1).contains(snapshot.spentFraction))
    }

    @Test
    func remindersAreOnlyInTheFutureAndUnique() async {
        let reminders = await loadedViewModel().reminders(now: now)
        #expect(reminders.allSatisfy { $0.date > now })
        #expect(Set(reminders.map(\.id)).count == reminders.count)
    }

    @Test
    func plannedRemindersArriveInTheMorningOfTheirDay() async {
        let viewModel = await loadedViewModel()
        let planned = viewModel.reminders(now: now).filter {
            if case .planned = $0.kind {
                true
            } else {
                false
            }
        }
        for reminder in planned {
            #expect(Calendar.current.component(.hour, from: reminder.date) == HomeViewModel.reminderHour)
        }
    }

    @Test
    func aCardWithAPaymentDayGetsAReminderBeforeIt() async throws {
        // The sample's single-currency card is due on the 15th.
        let viewModel = await loadedViewModel()
        let payment = try #require(viewModel.reminders(now: now).first { $0.kind == .payment(SampleData.IDs.visa) })
        let days = viewModel.overview?.paymentReminderDaysBefore ?? 0
        let due = try #require(Calendar.current.date(byAdding: .day, value: days, to: payment.date))
        #expect(Calendar.current.component(.day, from: due) == 15)
    }
}
