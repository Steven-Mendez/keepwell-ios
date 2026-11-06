import Domain
import DomainSamples
import Foundation
import Testing
@testable import HomeDomain
@testable import HomePresentation

@MainActor
@Suite("Home debts")
struct HomeDebtsTests {
    private let now = SampleData.defaultReferenceDate

    private func loadedViewModel(withDebts: Bool = true) async -> HomeViewModel {
        let store = InMemoryStore(sample: .standard)
        let viewModel = HomeViewModel(
            getOverview: DefaultGetHomeOverviewUseCase(
                accounts: store, cards: store, transactions: store, categories: store, settings: store,
                loans: withDebts ? store : nil, personalDebts: withDebts ? store : nil, now: { [now] in now },
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store),
            getPreferredName: DefaultGetPreferredNameUseCase(profile: InMemoryPasscodeStore()),
        )
        await viewModel.load()
        return viewModel
    }

    @Test
    func theCardShowsTheNextInstallmentAndTotalsPerCurrency() async throws {
        let viewModel = await loadedViewModel()
        let overview = try #require(viewModel.overview)
        let loan = try #require(viewModel.nextLoan(overview))
        #expect(loan.next?.number == 3)
        #expect(viewModel.debtTotal(overview.debtTotals.youOwe, hidden: false) == "C$55,000.00 · $40.00")
        #expect(viewModel.debtTotal(overview.debtTotals.owedToYou, hidden: true) == "••••")
        #expect(viewModel.installmentLine(loan, hidden: true)?.hasSuffix("· ••••") == true)
    }

    @Test
    func theNextInstallmentIsRemindedAsManyDaysAheadAsCardPayments() async throws {
        let viewModel = await loadedViewModel()
        let overview = try #require(viewModel.overview)
        let reminder = try #require(viewModel.reminders(now: now).first { $0.kind == .loanInstallment(SampleData.IDs.motorbikeLoan) })
        let due = try #require(overview.loans.first?.next?.dueDate)
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: reminder.date),
            to: Calendar.current.startOfDay(for: due),
        ).day
        #expect(days == overview.paymentReminderDaysBefore)
        #expect(Calendar.current.component(.hour, from: reminder.date) == HomeViewModel.reminderHour)
        #expect(reminder.body == "Installment 3 of 12 · C$5,500.00")
    }

    @Test
    func withoutRepositoriesThereAreNoDebts() async {
        let viewModel = await loadedViewModel(withDebts: false)
        #expect(viewModel.overview?.loans.isEmpty == true)
        #expect(viewModel.overview?.debtTotals.youOwe.isEmpty == true)
    }
}
