import Domain
import DomainSamples
import Foundation
import RecurringDomain
import Testing
@testable import RecurringPresentation

@Suite("New subscription form")
@MainActor
struct SubscriptionFormTests {
    private let ruleID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xF0, 0x14))
    private let billingDay = SampleData.defaultReferenceDate.addingTimeInterval(86400 * 4)

    @Test
    func itOpensShortAsAnExpenseInSubscriptionsMarkedAsOne() async {
        let viewModel = RecurringPreview.editorViewModel(ruleID: nil, isNewSubscription: true)
        await viewModel.load()
        #expect(viewModel.title == "New subscription")
        #expect(!viewModel.showsAllFields)
        #expect(viewModel.kind == .expense)
        #expect(viewModel.categoryID == Subscriptions.categoryID)
        #expect(viewModel.isSubscription)
        #expect(viewModel.method != nil)
        #expect(!viewModel.shortFormNeedsChoices)
        #expect(viewModel.subscriptionPeriod == .monthly)
        viewModel.showMoreOptions()
        #expect(viewModel.showsAllFields)

        let full = RecurringPreview.editorViewModel(ruleID: nil)
        await full.load()
        #expect(full.showsAllFields)
        #expect(full.title == "New recurring")
    }

    @Test
    func theFourPeriodsAreMonthlySchedulesOrYearly() {
        let schedules = SubscriptionPeriod.allCases.map { [$0.frequency.rawValue, "\($0.interval)"] }
        #expect(schedules == [["monthly", "1"], ["monthly", "3"], ["monthly", "6"], ["yearly", "1"]])
        #expect(SubscriptionPeriod(frequency: .monthly, interval: 6) == .halfYearly)
        #expect(SubscriptionPeriod(frequency: .monthly, interval: 2) == nil)
        #expect(SubscriptionPeriod(frequency: .weekly, interval: 1) == nil)
    }

    @Test
    func theNextChargeFollowsThePeriodAndBillingDayBeforeSaving() async throws {
        let viewModel = RecurringPreview.editorViewModel(ruleID: nil, isNewSubscription: true)
        await viewModel.load()
        #expect(viewModel.nextCharge == "Today")
        // A billing day already past: the next charge is one period after it.
        let calendar = Calendar.current
        let start = try #require(calendar.date(byAdding: .day, value: -10, to: SampleData.defaultReferenceDate))
        viewModel.startDate = start
        viewModel.subscriptionPeriod = .quarterly
        #expect(viewModel.frequency == .monthly)
        #expect(viewModel.interval == 3)
        let expected = try #require(calendar.date(byAdding: .month, value: 3, to: start))
        let sameYear = calendar.component(.year, from: expected) == calendar.component(.year, from: SampleData.defaultReferenceDate)
        let style: Date.FormatStyle = sameYear ? .dateTime.day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year()
        #expect(viewModel.nextCharge == expected.formatted(style).replacingOccurrences(of: ".", with: ""))
    }

    @Test
    func fourFieldsSaveTheSameRuleAsTheFullForm() async throws {
        let shortStore = InMemoryStore(sample: .standard)
        let short = RecurringPreview.editorViewModel(
            ruleID: nil, isNewSubscription: true, store: shortStore, makeID: { ruleID },
        )
        await short.load()
        short.name = "Music"
        short.amountText = "9.99"
        short.subscriptionPeriod = .quarterly
        short.startDate = billingDay
        #expect(short.canSave)
        #expect(await short.save())

        let fullStore = InMemoryStore(sample: .standard)
        let full = RecurringPreview.editorViewModel(ruleID: nil, store: fullStore, makeID: { ruleID })
        await full.load()
        full.name = "Music"
        full.amountText = "9.99"
        full.selectCategory(Subscriptions.categoryID)
        full.frequency = .monthly
        full.interval = 3
        full.startDate = billingDay
        #expect(await full.save())

        let saved = try #require(await shortStore.fetchRecurringRules().first { $0.id == ruleID })
        let expected = try #require(await fullStore.fetchRecurringRules().first { $0.id == ruleID })
        #expect(saved == expected)
        #expect(saved.isSubscription)
        #expect(saved.categoryID == Subscriptions.categoryID)
    }

    @Test
    func withoutTheSubscriptionsCategoryTheShortFormAsksForOne() async {
        let store = InMemoryStore(sample: .standard)
        await store.deleteCategory(id: Subscriptions.categoryID)
        let viewModel = RecurringPreview.editorViewModel(ruleID: nil, isNewSubscription: true, store: store)
        await viewModel.load()
        #expect(viewModel.categoryID == nil)
        #expect(viewModel.shortFormNeedsChoices)
        #expect(viewModel.isSubscription)
    }
}
