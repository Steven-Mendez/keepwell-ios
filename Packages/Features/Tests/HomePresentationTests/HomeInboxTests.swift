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

    private var visa: String {
        SampleData.IDs.visa.uuidString.lowercased()
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
            listNotificationStates: DefaultListNotificationStatesUseCase(repository: store),
            changeNotifications: DefaultChangeNotificationsUseCase(repository: store),
            pruneNotificationStates: DefaultPruneNotificationStatesUseCase(repository: store),
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
        let payment = try #require(items.first { $0.id == "payment:\(visa):2026-11-15" })
        #expect(payment.title == "Visa ··9012: payment in 2 days")
        #expect(payment.destination == .creditCard(accountID: SampleData.IDs.visa))
    }

    @Test
    func aCardPaymentOutsideTheWindowIsLeftOut() async throws {
        let viewModel = await loadedViewModel()
        #expect(try !viewModel.inbox(now: day(11, 11), calendar: calendar).contains { $0.kind == .payment })
        // The due day itself still counts: it is the last chance to pay.
        #expect(try viewModel.inbox(now: day(11, 15), calendar: calendar).first { $0.kind == .payment }?.title
            == "Visa ··9012: due today")
    }

    @Test
    func aStatementClosingTodayShowsOnlyOnThatDay() async throws {
        // The sample's card closes on the 28th.
        let viewModel = await loadedViewModel()
        let id = "cutoff:\(visa):2026-10-28"
        #expect(try viewModel.inbox(now: day(10, 28), calendar: calendar).first { $0.id == id }?.title
            == "Visa ··9012: statement closes today")
        #expect(try !viewModel.inbox(now: day(10, 27), calendar: calendar).contains { $0.id == id })
        #expect(try !viewModel.inbox(now: day(10, 29), calendar: calendar).contains { $0.id == id })
    }

    @Test
    func aSubscriptionRenewingTomorrowShows() async throws {
        let items = await loadedViewModel().inbox(now: now, calendar: calendar)
        let rule = SampleData.IDs.streamingRule.uuidString.lowercased()
        let renewal = try #require(items.first { $0.id.hasPrefix("renewal:\(rule):") })
        #expect(renewal.title == "Streaming renews tomorrow")
        #expect(renewal.destination == .recurring)
    }

    @Test
    func budgetsShowFromEightyPercentAndWhenSpent() async throws {
        let store = InMemoryStore(sample: .standard)
        let month = try #require(await loadedViewModel(store).overview?.month)
        let spent = try #require(month.categories.first)
        let id = "budget:\(spent.categoryID):2026-10:"

        try await budgeting(store, spent.categoryID, spent.amount / #require(Decimal(string: "0.8")))
        let near = try #require(await loadedViewModel(store).inbox(now: now, calendar: calendar).first { $0.id == id + "near" })
        #expect(near.title.hasSuffix("is close to its budget"))
        #expect(near.tone == .pending)

        try await budgeting(store, spent.categoryID, spent.amount)
        let over = try #require(await loadedViewModel(store).inbox(now: now, calendar: calendar).first { $0.id == id + "over" })
        #expect(over.title.hasSuffix("went over its budget"))
        #expect(over.tone == .negative)

        try await budgeting(store, spent.categoryID, spent.amount * 2)
        #expect(await !loadedViewModel(store).inbox(now: now, calendar: calendar).contains { $0.id.hasPrefix(id) })
    }

    @Test
    func plannedDraftsStayOnHome() async {
        let viewModel = await loadedViewModel()
        #expect(viewModel.overview?.planned.isEmpty == false)
        let items = viewModel.inbox(now: now, calendar: calendar)
        #expect(!items.contains { $0.kind == .planned })
        #expect(Set(items.map(\.id)).count == items.count)
    }

    private func proposing(_ store: InMemoryStore) async -> RecurringRule {
        let rule = RecurringRule(
            name: "Gym", kind: .expense, categoryID: "health", amount: 25, currency: "USD", accountID: SampleData.IDs.savings,
            frequency: .monthly, startDate: now, isPaused: true, source: .mcp,
        )
        await store.save(rule)
        return rule
    }

    @Test
    func anAssistantsProposalIsARowOnTopWithItsRule() async throws {
        let store = InMemoryStore(sample: .standard)
        let rule = await proposing(store)
        let viewModel = await loadedViewModel(store)
        let sections = viewModel.inboxSections(now: now, calendar: calendar)
        let proposal = try #require(sections.proposals.first)
        #expect(proposal.id == "proposal:\(rule.id.uuidString.lowercased())")
        #expect(proposal.proposal == rule)
        #expect(proposal.title == "Gym")
        #expect(proposal.destination == .recurring)
        #expect(!sections.days.contains { $0.items.contains { $0.kind == .proposal } })
    }

    @Test
    func rowsAreGroupedByDayNewestFirst() async {
        let viewModel = await loadedViewModel()
        let sections = viewModel.inboxSections(now: now, calendar: calendar).days
        #expect(!sections.isEmpty)
        #expect(sections.map(\.day) == sections.map(\.day).sorted(by: >))
        #expect(sections.allSatisfy { section in section.items.allSatisfy { $0.date == section.day } })
        #expect(sections.first?.title == "Today")
    }

    @Test
    func everythingStartsUnreadAndOnlyUnreadOnesCountOnTheBell() async throws {
        let viewModel = await loadedViewModel()
        let items = viewModel.inbox(now: now, calendar: calendar)
        #expect(items.allSatisfy { !$0.isRead })
        #expect(viewModel.inboxCount(now: now) == items.count)

        let first = try #require(items.first)
        await viewModel.open(first)
        #expect(viewModel.inbox(now: now, calendar: calendar).first { $0.id == first.id }?.isRead == true)
        #expect(viewModel.inboxCount(now: now) == items.count - 1)
    }

    @Test
    func toggleReadFlipsItBothWays() async throws {
        let viewModel = await loadedViewModel()
        let first = try #require(viewModel.inbox(now: now, calendar: calendar).first)
        await viewModel.toggleRead(first)
        let read = try #require(viewModel.inbox(now: now, calendar: calendar).first { $0.id == first.id })
        #expect(read.isRead)
        await viewModel.toggleRead(read)
        #expect(viewModel.inbox(now: now, calendar: calendar).first { $0.id == first.id }?.isRead == false)
    }

    @Test
    func deletingHidesItAndUndoBringsItBackRead() async throws {
        let viewModel = await loadedViewModel()
        let first = try #require(viewModel.inbox(now: now, calendar: calendar).first)
        await viewModel.delete(first)
        #expect(!viewModel.inbox(now: now, calendar: calendar).contains { $0.id == first.id })
        let offer = try #require(viewModel.undoOffer)
        #expect(offer.ids == [first.id])

        await viewModel.undo(offer)
        #expect(viewModel.undoOffer == nil)
        #expect(viewModel.inbox(now: now, calendar: calendar).first { $0.id == first.id }?.isRead == true)
    }

    @Test
    func markAllReadAndDeleteReadKeepProposalsForTheirAnswer() async {
        let store = InMemoryStore(sample: .standard)
        _ = await proposing(store)
        let viewModel = await loadedViewModel(store)
        let before = viewModel.inbox(now: now, calendar: calendar)
        await viewModel.markAllRead(now: now)
        #expect(viewModel.inboxCount(now: now) == 0)
        await viewModel.deleteRead(now: now)
        let left = viewModel.inbox(now: now, calendar: calendar)
        #expect(left.map(\.kind) == [.proposal])
        #expect(viewModel.undoOffer?.ids.count == before.count - 1)
    }

    @Test
    func theSystemIsToldWhatWasReadOrDeleted() async throws {
        let viewModel = await loadedViewModel()
        let items = viewModel.inbox(now: now, calendar: calendar)
        let (read, deleted) = try (#require(items.first), #require(items.last))
        await viewModel.open(read)
        await viewModel.delete(deleted)
        #expect(Set(viewModel.settledNotificationIDs) == [read.id, deleted.id])
        #expect(viewModel.statesRevision > 0)
        // Nothing read or deleted is scheduled again.
        let scheduled = Set(viewModel.reminders(now: now, calendar: calendar).map(\.id))
        #expect(scheduled.isDisjoint(with: viewModel.settledNotificationIDs))
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
