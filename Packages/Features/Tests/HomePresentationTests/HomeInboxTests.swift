import Domain
import DomainSamples
import Foundation
import RecurringDomain
import Testing
@testable import HomeDomain
@testable import HomePresentation

/// The notifications list: what applies on a given day, with nothing stored.
@MainActor
@Suite("Home inbox")
struct HomeInboxTests {
    private let now = SampleData.defaultReferenceDate
    private let calendar = Calendar.current

    private func day(_ month: Int, _ day: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)))
    }

    private func loadedViewModel(_ store: InMemoryStore = InMemoryStore(sample: .standard)) async -> HomeViewModel {
        let now = now
        let viewModel = HomeViewModel(
            getOverview: DefaultGetHomeOverviewUseCase(
                accounts: store, cards: store, transactions: store, categories: store, settings: store,
                recurringRules: store, now: { now },
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store),
            getPreferredName: DefaultGetPreferredNameUseCase(profile: InMemoryPasscodeStore()),
        )
        await viewModel.load()
        return viewModel
    }

    private func budgeting(_ store: InMemoryStore, _ id: String, _ amount: Decimal) async throws {
        let category = try #require(await store.fetchCategories().first { $0.id == id })
        await store.save(TransactionCategory(
            id: category.id, name: category.name, kind: category.kind, icon: category.icon, color: category.color,
            isRenamed: category.isRenamed, monthlyBudget: Money(amount, "USD"),
        ))
    }

    @Test
    func aCardPaymentInsideTheReminderWindowShowsWithTheDaysLeft() async throws {
        // The sample's card is due on the 15th and the window is three days.
        let items = try await loadedViewModel().inbox(now: day(11, 13), calendar: calendar)
        let payment = try #require(items.first { $0.id == "payment-\(SampleData.IDs.visa)" })
        #expect(payment.title == "Visa ··9012: payment in 2 days")
        #expect(payment.destination == .creditCard(accountID: SampleData.IDs.visa))
    }

    @Test
    func aCardPaymentOutsideTheWindowIsLeftOut() async throws {
        let viewModel = await loadedViewModel()
        #expect(try !viewModel.inbox(now: day(11, 11), calendar: calendar).contains { $0.id.hasPrefix("payment-") })
        // The due day itself still counts: it is the last chance to pay.
        #expect(try viewModel.inbox(now: day(11, 15), calendar: calendar).first { $0.id.hasPrefix("payment-") }?.title
            == "Visa ··9012: due today")
    }

    @Test
    func aStatementClosingTodayShowsOnlyOnThatDay() async throws {
        // The sample's card closes on the 28th.
        let viewModel = await loadedViewModel()
        let id = "cutoff-\(SampleData.IDs.visa)"
        #expect(try viewModel.inbox(now: day(10, 28), calendar: calendar).first { $0.id == id }?.title
            == "Visa ··9012: statement closes today")
        #expect(try !viewModel.inbox(now: day(10, 27), calendar: calendar).contains { $0.id == id })
        #expect(try !viewModel.inbox(now: day(10, 29), calendar: calendar).contains { $0.id == id })
    }

    @Test
    func aSubscriptionRenewingTomorrowShows() async throws {
        let items = await loadedViewModel().inbox(now: now, calendar: calendar)
        let renewal = try #require(items.first { $0.id == "renews-\(SampleData.IDs.streamingRule)" })
        #expect(renewal.title == "Streaming renews tomorrow")
        #expect(renewal.destination == .recurring)
    }

    @Test
    func budgetsShowFromEightyPercentAndWhenSpent() async throws {
        let store = InMemoryStore(sample: .standard)
        let month = try #require(await loadedViewModel(store).overview?.month)
        let spent = try #require(month.categories.first)
        let id = "budget-\(spent.categoryID)"

        try await budgeting(store, spent.categoryID, spent.amount / #require(Decimal(string: "0.8")))
        let near = try #require(await loadedViewModel(store).inbox(now: now, calendar: calendar).first { $0.id == id })
        #expect(near.title.hasSuffix("is close to its budget"))
        #expect(near.tone == .pending)

        try await budgeting(store, spent.categoryID, spent.amount)
        let over = try #require(await loadedViewModel(store).inbox(now: now, calendar: calendar).first { $0.id == id })
        #expect(over.title.hasSuffix("went over its budget"))
        #expect(over.tone == .negative)

        try await budgeting(store, spent.categoryID, spent.amount * 2)
        #expect(await !loadedViewModel(store).inbox(now: now, calendar: calendar).contains { $0.id == id })
    }

    @Test
    func plannedDraftsStayOnHome() async {
        let viewModel = await loadedViewModel()
        #expect(viewModel.overview?.planned.isEmpty == false)
        let items = viewModel.inbox(now: now, calendar: calendar)
        #expect(!items.contains { $0.id.hasPrefix("planned") })
        #expect(Set(items.map(\.id)).count == items.count)
    }

    @Test
    func theCountAddsTheRulesAnAssistantProposed() async {
        let store = InMemoryStore(sample: .standard)
        await store.save(RecurringRule(
            name: "Gym", kind: .expense, categoryID: "health", amount: 25, currency: "USD", accountID: SampleData.IDs.savings,
            frequency: .monthly, startDate: now, isPaused: true, source: .mcp,
        ))
        let viewModel = await loadedViewModel(store)
        #expect(viewModel.inboxCount(now: now) == viewModel.inbox(now: now, calendar: viewModel.calendar).count + 1)
    }

    @Test
    func nothingShowsBeforeHomeLoads() {
        let store = InMemoryStore(sample: .standard)
        let viewModel = HomeViewModel(
            getOverview: DefaultGetHomeOverviewUseCase(
                accounts: store, cards: store, transactions: store, categories: store, settings: store, now: { .now },
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store),
            getPreferredName: DefaultGetPreferredNameUseCase(profile: InMemoryPasscodeStore()),
        )
        #expect(viewModel.inbox().isEmpty)
        #expect(viewModel.inboxCount() == 0)
    }
}
