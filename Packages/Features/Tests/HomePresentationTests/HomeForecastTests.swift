import Domain
import DomainSamples
import Foundation
import Testing
@testable import HomeDomain
@testable import HomePresentation

@MainActor
@Suite("Home end of month and price increases")
struct HomeForecastTests {
    private let now = SampleData.defaultReferenceDate

    private func loadedViewModel(_ store: InMemoryStore) async -> HomeViewModel {
        let viewModel = HomeViewModel(
            getOverview: DefaultGetHomeOverviewUseCase(
                accounts: store, cards: store, transactions: store, categories: store, settings: store,
                recurringRules: store, now: { [now] in now },
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store),
            getPreferredName: DefaultGetPreferredNameUseCase(profile: InMemoryPasscodeStore()),
        )
        await viewModel.load()
        return viewModel
    }

    @Test
    func theForecastListsItsLinesAndHidesThemWithBalances() async throws {
        let viewModel = await loadedViewModel(InMemoryStore(sample: .standard))
        let forecast = try #require(viewModel.overview?.forecast)
        let lines = viewModel.forecastLines(forecast, hidden: false)
        #expect(lines.map(\.title) == ["Available today", "Planned income", "Planned expenses", "Card payments", "Usual spending"])
        #expect(lines.dropFirst(2).allSatisfy { $0.amount.hasPrefix("−") || $0.amount == "$0" })
        #expect(viewModel.forecastTotal(forecast, hidden: false).hasPrefix("≈ "))
        #expect(viewModel.forecastLines(forecast, hidden: true).allSatisfy { $0.amount == HomeViewModel.maskedAmount })
        #expect(viewModel.forecastTotal(forecast, hidden: true) == HomeViewModel.maskedAmount)
    }

    @Test
    func aSubscriptionThatWentUpIsShownAndNotifiedOncePerCharge() async throws {
        let store = InMemoryStore(sample: .standard)
        let calendar = Calendar.current
        let charge = { (amount: Decimal, daysAgo: Int) in
            Transaction(
                date: calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now,
                description: "Video club", kind: .expense, categoryID: Subscriptions.categoryID,
                amount: amount, currency: "USD", accountID: SampleData.IDs.mastercard,
                cardID: SampleData.IDs.mastercardHolder, exchangeRate: .single("USD"),
            )
        }
        let newest = charge(12, 2)
        await store.save(charge(9, 32))
        await store.save(newest)

        let viewModel = await loadedViewModel(store)
        let alert = try #require(viewModel.priceIncreaseAlerts.first)
        #expect(alert.title == "Video club went up in price")
        #expect(alert.body == "Now $12.00, before $9.00.")
        let reminders = viewModel.reminders(now: now).filter { $0.kind == .price }
        #expect(reminders.map(\.id) == ["price:\(newest.id.uuidString.lowercased())"])
        // It reports something that already happened: told once, right away.
        #expect(reminders.allSatisfy { $0.isOneShot && $0.date >= now })
    }
}
