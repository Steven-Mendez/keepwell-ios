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
    func theStatusLineCountsWhatIsDueWithPlurals() {
        #expect(HomeViewModel.statusLine(HomeStatus()) == "All caught up")
        #expect(HomeViewModel.statusLine(HomeStatus(toConfirm: 2, dueTomorrow: 1)) == "2 payments to confirm · 1 due tomorrow")
        #expect(
            HomeViewModel.statusLine(HomeStatus(toConfirm: 1, overdue: 2, dueToday: 3))
                == "1 payment to confirm · 2 installments overdue · 3 due today",
        )
        #expect(HomeViewModel.statusLine(HomeStatus(overdue: 1)) == "1 installment overdue")
        #expect(
            HomeViewModel.statusLine(HomeStatus(toConfirm: 1, overdue: 2, overdueDebts: 1, dueToday: 1, dueTomorrow: 2))
                == "1 payment to confirm · 2 installments overdue · 1 debt overdue · 1 due today · 2 due tomorrow",
        )
        #expect(HomeViewModel.statusLine(HomeStatus(overdueDebts: 2)) == "2 debts overdue")
        #expect(
            HomeViewModel.statusLine(HomeStatus(overdueDebts: 2, dueToday: 1, dueTomorrow: 1))
                == "2 debts overdue · 1 due today · 1 due tomorrow",
        )
    }

    @Test
    func theStatusLineFollowsTheDraftsHomeLists() async throws {
        // The sample's "today" is Oct 22 and its drafts are later: nothing is late yet.
        let viewModel = await loadedViewModel()
        #expect(viewModel.statusLine() != nil)
        let overview = try #require(viewModel.overview)
        let late = overview.planned.count { Calendar.current.startOfDay(for: $0.date) <= Calendar.current.startOfDay(for: now) }
        let status = HomeStatus(overview)
        #expect(status.toConfirm == late)
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
