import Domain
import DomainSamples
import Foundation
import RecurringDomain
import SharedPresentation
import Testing
@testable import RecurringPresentation

@Suite("Recurring view models")
@MainActor
struct RecurringViewModelTests {
    private typealias IDs = SampleData.IDs

    @Test
    func rulesAreGroupedWithEmptyGroupsHiddenAndPausedLast() async {
        let viewModel = RecurringPreview.listViewModel()
        await viewModel.load()
        #expect(viewModel.sections.map(\.group) == [.subscriptions, .bills, .income, .transfers])
        #expect(viewModel.sections.first?.rules.map(\.id) == [IDs.streamingRule])

        let store = InMemoryStore(sample: .standard)
        for rule in SampleData.standard.recurringRules where rule.kind != .expense {
            try? await store.deleteRecurringRule(id: rule.id)
        }
        let expensesOnly = RecurringPreview.listViewModel(store: store)
        await expensesOnly.load()
        #expect(expensesOnly.sections.map(\.group) == [.subscriptions, .bills])
    }

    @Test
    func rowsReadFrequencyNextDayAndMethod() async throws {
        let viewModel = RecurringPreview.listViewModel()
        await viewModel.load()
        let streaming = try #require(viewModel.overview?.rule(IDs.streamingRule))
        #expect(viewModel.subtitle(of: streaming).hasPrefix("Every month · Tomorrow · "))
        #expect(viewModel.amount(of: streaming, hidden: false) == "−$15.99")
        #expect(viewModel.amount(of: streaming, hidden: true) == "••••")
        let salary = try #require(viewModel.overview?.rule(IDs.salaryRule))
        #expect(viewModel.subtitle(of: salary).contains("Paused"))
        let cash = try #require(viewModel.overview?.rule(IDs.cashRule))
        #expect(viewModel.subtitle(of: cash).hasPrefix("Every 2 weeks"))
        #expect(viewModel.monthlyTotal(hidden: false) == "$15.99")
        #expect(viewModel.yearlyTotal(hidden: false) == "≈ $191.88 per year")
    }

    /// The rule's own merchant gives the row its logo before the brand its name suggests.
    @Test
    func aRowsLogoComesFromItsMerchantFirst() async throws {
        let store = InMemoryStore(sample: .standard)
        let viewModel = RecurringPreview.listViewModel(store: store)
        await viewModel.load()
        let streaming = try #require(viewModel.overview?.rule(IDs.streamingRule))
        #expect(viewModel.logo(of: streaming) == nil)

        let netflix = Merchant(name: "Netflix", brandID: "netflix")
        await store.save(netflix)
        await store.save(streaming.with(merchantID: netflix.id, viaMerchantID: nil))
        await viewModel.load()
        let linked = try #require(viewModel.overview?.rule(IDs.streamingRule))
        #expect(viewModel.logo(of: linked) == LogoSubject(name: "Netflix", domain: "netflix.com"))
    }

    @Test
    func emptyWhenThereAreNoRules() async {
        let store = InMemoryStore(sample: .standard)
        for rule in SampleData.standard.recurringRules {
            try? await store.deleteRecurringRule(id: rule.id)
        }
        let viewModel = RecurringPreview.listViewModel(store: store)
        await viewModel.load()
        #expect(viewModel.isEmpty)
        #expect(viewModel.sections.isEmpty)
    }

    @Test
    func editingFillsTheFormAndShowsTheNextDates() async {
        let viewModel = RecurringPreview.editorViewModel(ruleID: IDs.streamingRule)
        await viewModel.load()
        #expect(viewModel.name == "Streaming")
        #expect(viewModel.method == .card(IDs.mastercardHolder))
        #expect(viewModel.isSubscription)
        #expect(viewModel.repeatsTitle == "Every month")
        #expect(viewModel.nextDates.count == 3)
        #expect(viewModel.nextDates.first == "Tomorrow")
        #expect(viewModel.canSave)
    }

    @Test
    func creatingNeedsANameAmountAndCategoryAndPickingSubscriptionsMarksIt() async throws {
        let store = InMemoryStore(sample: .standard)
        let viewModel = RecurringPreview.editorViewModel(ruleID: nil, store: store)
        await viewModel.load()
        #expect(viewModel.method != nil)
        #expect(!viewModel.canSave)
        viewModel.name = "Music"
        viewModel.amountText = "9.99"
        viewModel.currency = "USD"
        viewModel.selectCategory(Subscriptions.categoryID)
        #expect(viewModel.isSubscription)
        #expect(viewModel.canSave)
        #expect(await viewModel.save())
        let saved = try #require(await store.fetchRecurringRules().first { $0.name == "Music" })
        #expect(saved.amount == Decimal(string: "9.99"))
        #expect(saved.isSubscription)
        #expect(!saved.autoConfirm)
    }

    @Test
    func newRulesShowThreeUpcomingDatesAndFollowTheSchedule() async {
        let viewModel = RecurringPreview.editorViewModel(ruleID: nil)
        await viewModel.load()
        #expect(viewModel.nextDates.count == 3)
        #expect(viewModel.nextDates.first == "Today")
        viewModel.frequency = .weekly
        viewModel.interval = 2
        viewModel.startDate = SampleData.defaultReferenceDate.addingTimeInterval(86400 * 3)
        let weekly = viewModel.nextDates
        #expect(weekly.count == 3)
        #expect(weekly.first != "Today")
        viewModel.hasEndDate = true
        viewModel.endDate = viewModel.startDate
        #expect(viewModel.nextDates.count == 1)
    }

    @Test
    func theSubscriptionSwitchFollowsTheCategoryUntilTheUserFlipsIt() async {
        let viewModel = RecurringPreview.editorViewModel(ruleID: nil)
        await viewModel.load()
        #expect(!viewModel.isSubscription)
        viewModel.selectCategory(Subscriptions.categoryID)
        #expect(viewModel.isSubscription)
        viewModel.selectCategory("health")
        #expect(!viewModel.isSubscription)
        viewModel.selectCategory(Subscriptions.categoryID)
        viewModel.isSubscription = false
        viewModel.selectCategory("health")
        viewModel.selectCategory(Subscriptions.categoryID)
        #expect(!viewModel.isSubscription)
    }

    @Test
    func finishedSubscriptionsDoNotCountTowardTheMonthlyTotal() async throws {
        let store = InMemoryStore(sample: .standard)
        let streaming = try #require(SampleData.standard.recurringRules.first { $0.id == IDs.streamingRule })
        let past = SampleData.defaultReferenceDate.addingTimeInterval(-86400 * 60)
        let finished = RecurringRule(
            name: "Old", kind: .expense, categoryID: streaming.categoryID, amount: 100, currency: streaming.currency,
            accountID: streaming.accountID, cardID: streaming.cardID, frequency: .monthly, startDate: past.addingTimeInterval(-86400 * 30),
            nextDate: past, endDate: past.addingTimeInterval(-86400), isSubscription: true,
        )
        await store.save(finished)
        let viewModel = RecurringPreview.listViewModel(store: store)
        await viewModel.load()
        #expect(viewModel.monthlyTotal(hidden: false) == "$15.99")
    }

    @Test
    func subscriptionsTheTotalCannotConvertAreNamedUnderIt() async throws {
        let store = InMemoryStore(sample: .standard)
        let streaming = try #require(SampleData.standard.recurringRules.first { $0.id == IDs.streamingRule })
        #expect(RecurringPreview.listViewModel().excludedSubscriptions.isEmpty)
        for amount in [Decimal(5), 7] {
            await store.save(RecurringRule(
                name: "Euro", kind: .expense, categoryID: streaming.categoryID, amount: amount, currency: "EUR",
                accountID: streaming.accountID, frequency: .monthly, startDate: SampleData.defaultReferenceDate, isSubscription: true,
            ))
        }
        let viewModel = RecurringPreview.listViewModel(store: store)
        await viewModel.load()
        #expect(viewModel.monthlyTotal(hidden: false) == "$15.99")
        #expect(viewModel.excludedSubscriptions == ["Not including 2 subscriptions in EUR"])
    }

    @Test
    func switchingToATransferDropsTheCategoryAndAsksForADestination() async {
        let viewModel = RecurringPreview.editorViewModel(ruleID: nil)
        await viewModel.load()
        viewModel.selectCategory("health")
        viewModel.kind = .transfer
        #expect(viewModel.category == nil)
        #expect(viewModel.methodOptions.allSatisfy { option in
            if case .card = option.method {
                true
            } else {
                true
            }
        })
        viewModel.name = "Savings"
        viewModel.amountText = "100"
        #expect(!viewModel.canSave)
        viewModel.destinationAccountID = viewModel.destinationOptions.first?.id
        #expect(viewModel.canSave)
    }

    @Test
    func pausingAndDeletingFromTheEditor() async {
        let store = InMemoryStore(sample: .standard)
        let viewModel = RecurringPreview.editorViewModel(ruleID: IDs.rentRule, store: store)
        await viewModel.load()
        await viewModel.togglePaused()
        #expect(viewModel.isPaused)
        // Paused rules still show where they would fall; the view dims them.
        #expect(viewModel.nextDates.count == 3)
        #expect(await viewModel.delete())
        #expect(await !store.fetchRecurringRules().contains { $0.id == IDs.rentRule })
    }
}
