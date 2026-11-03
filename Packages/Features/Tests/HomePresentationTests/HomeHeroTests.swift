import Domain
import DomainSamples
import Foundation
import Testing
@testable import HomeDomain
@testable import HomePresentation

@MainActor
@Suite("Home hero")
struct HomeHeroTests {
    private let now = SampleData.defaultReferenceDate

    private func loadedViewModel(calendar: Calendar = .current, name: String? = nil) async -> HomeViewModel {
        let store = InMemoryStore(sample: .standard)
        let viewModel = HomeViewModel(
            getOverview: DefaultGetHomeOverviewUseCase(
                accounts: store, cards: store, transactions: store, categories: store, settings: store, now: { [now] in now },
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store),
            getPreferredName: DefaultGetPreferredNameUseCase(profile: InMemoryPasscodeStore(name: name)),
            calendar: calendar,
        )
        await viewModel.load()
        return viewModel
    }

    @Test
    func carouselStartsWithNetWorthThenEachAccountThenCardDebt() async throws {
        let viewModel = await loadedViewModel()
        let overview = try #require(viewModel.overview)
        let pages = viewModel.balancePages(overview)
        #expect(pages.first?.kind == .netWorth)
        #expect(pages.first?.amount == overview.netWorth)
        #expect(pages.dropFirst().prefix(overview.balances.count).map(\.kind) == overview.balances.map { .account($0.account.id) })
        #expect(pages.last?.kind == .cardDebt)
        #expect(pages.count == overview.balances.count + 2)
    }

    @Test
    func accountPagesKeepTheirOwnCurrency() async throws {
        let viewModel = await loadedViewModel()
        let overview = try #require(viewModel.overview)
        let pages = viewModel.balancePages(overview)
        for line in overview.balances {
            let page = try #require(pages.first { $0.kind == .account(line.account.id) })
            #expect(page.amount == line.balance)
            // Only balances outside the principal get the "≈" conversion under them.
            #expect((page.caption != nil) == (line.balance.currency != overview.settings.principal))
        }
    }

    @Test
    func hiddenBalancesShowTheMask() async throws {
        let viewModel = await loadedViewModel()
        let overview = try #require(viewModel.overview)
        let hidden = viewModel.parts(overview.netWorth, hidden: true)
        #expect(hidden.whole == HomeViewModel.maskedAmount)
        #expect(hidden.cents.isEmpty)
        #expect(viewModel.visible("$1.00", hidden: true) == HomeViewModel.maskedAmount)
        #expect(viewModel.visible("$1.00", hidden: false) == "$1.00")
        #expect(!viewModel.plannedCaption(overview, hidden: true).contains("$"))
    }

    @Test
    func visibleAmountsSplitTheCents() async {
        let viewModel = await loadedViewModel()
        let parts = viewModel.parts(Money(Decimal(string: "11157.46") ?? 0, "USD"), hidden: false)
        #expect(parts.whole == "$11,157")
        #expect(parts.cents == ".46")
    }

    @Test(arguments: [(7, "Good morning"), (14, "Good afternoon"), (21, "Good evening"), (2, "Good evening")])
    func greetingFollowsTheTimeOfDay(hour: Int, expected: String) async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let viewModel = await loadedViewModel(calendar: calendar)
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: hour)))
        #expect(viewModel.greeting(at: date) == expected)
    }

    @Test(arguments: [(7, "Good morning, Steven"), (14, "Good afternoon, Steven"), (21, "Good evening, Steven")])
    func greetingNamesThePersonWhenTheyGaveAName(hour: Int, expected: String) async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let viewModel = await loadedViewModel(calendar: calendar, name: "Steven")
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: hour)))
        #expect(viewModel.greeting(at: date) == expected)
    }

    @Test
    func greetingPicksUpANameChangedInSettings() async {
        let store = InMemoryStore(sample: .standard)
        let profile = InMemoryPasscodeStore()
        let viewModel = HomeViewModel(
            getOverview: DefaultGetHomeOverviewUseCase(
                accounts: store, cards: store, transactions: store, categories: store, settings: store, now: { [now] in now },
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store),
            getPreferredName: DefaultGetPreferredNameUseCase(profile: profile),
        )
        await viewModel.load()
        #expect(viewModel.preferredName == nil)
        await profile.setPreferredName("Ana")
        await viewModel.load()
        #expect(viewModel.preferredName == "Ana")
    }
}
