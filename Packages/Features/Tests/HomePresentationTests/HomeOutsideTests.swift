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

    private func loadedViewModel(_ store: InMemoryStore = InMemoryStore(sample: .standard)) async -> HomeViewModel {
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
        #expect(reminders.filter { !$0.isOneShot }.allSatisfy { $0.date > now })
        #expect(Set(reminders.map(\.id)).count == reminders.count)
    }

    @Test
    func plannedRemindersArriveInTheMorningOfTheirDay() async {
        let viewModel = await loadedViewModel()
        let planned = viewModel.reminders(now: now).filter { $0.kind == .planned }
        #expect(!planned.isEmpty)
        for reminder in planned {
            #expect(reminder.id.hasPrefix("planned:"))
            #expect(reminder.transactionID != nil)
            #expect(Calendar.current.component(.hour, from: reminder.date) == LedgerNotifications.reminderHour)
        }
    }

    @Test
    func aCardWithAPaymentDayGetsAReminderBeforeIt() async throws {
        // The sample's single-currency card is due on the 15th.
        let viewModel = await loadedViewModel()
        let payment = try #require(viewModel.reminders(now: now)
            .first { $0.id == "payment:\(SampleData.IDs.visa.uuidString.lowercased()):2026-11-15" })
        let days = viewModel.overview?.paymentReminderDaysBefore ?? 0
        let due = try #require(Calendar.current.date(byAdding: .day, value: days, to: payment.date))
        #expect(Calendar.current.component(.day, from: due) == 15)
    }

    @Test
    func aCardWithACutoffDayGetsAReminderThatMorning() async throws {
        // The sample's single-currency card closes on the 28th.
        let reminder = try #require(await loadedViewModel().reminders(now: now).first { $0.kind == .cutoff })
        #expect(reminder.id == "cutoff:\(SampleData.IDs.visa.uuidString.lowercased()):2026-10-28")
        #expect(Calendar.current.component(.day, from: reminder.date) == 28)
        #expect(Calendar.current.component(.hour, from: reminder.date) == LedgerNotifications.reminderHour)
        #expect(reminder.title.contains("Visa ··9012"))
    }

    @Test
    func anExpiringCardIsRemindedOnTheFirstOfItsMonthWithItsServices() async throws {
        let store = InMemoryStore(sample: .standard)
        let next = try #require(Calendar.current.date(byAdding: .month, value: 2, to: now))
        let parts = Calendar.current.dateComponents([.year, .month], from: next)
        let holder = try #require(await store.fetchCards().first { $0.id == SampleData.IDs.visaHolder })
        try await store.save(holder.with(productName: "Premia", expiry: CardExpiry(month: parts.month ?? 1, year: parts.year ?? 2030)))
        for (index, day) in [-40, -10].enumerated() {
            try await store.save(Transaction(
                date: #require(Calendar.current.date(byAdding: .day, value: day, to: now)),
                description: index == 0 ? "Apple Music" : "apple music",
                kind: .expense,
                categoryID: "leisure",
                amount: 6.49,
                currency: "USD",
                accountID: SampleData.IDs.visa,
                cardID: SampleData.IDs.visaHolder,
                exchangeRate: .single("USD"),
            ))
        }

        let reminder = try #require(await loadedViewModel(store).reminders(now: now).first {
            $0.kind == .expiry
        })
        let day = Calendar.current.dateComponents([.month, .day, .hour], from: reminder.date)
        #expect(day.month == parts.month)
        #expect(day.day == 1)
        #expect(day.hour == LedgerNotifications.reminderHour)
        #expect(reminder.title == "Premia ··9012 expires this month")
        #expect(reminder.body.contains("apple music"))
    }

    @Test
    func anAlreadyExpiredCardIsNotReminded() async throws {
        let store = InMemoryStore(sample: .standard)
        let holder = try #require(await store.fetchCards().first { $0.id == SampleData.IDs.visaHolder })
        try await store.save(holder.with(productName: nil, expiry: CardExpiry(month: 1, year: 2020)))
        let reminders = await loadedViewModel(store).reminders(now: now)
        #expect(!reminders.contains { $0.kind == .expiry })
    }

    private func budgeting(_ store: InMemoryStore, _ id: String, _ amount: Decimal) async throws {
        let category = try #require(await store.fetchCategories().first { $0.id == id })
        await store.save(TransactionCategory(
            id: category.id, name: category.name, kind: category.kind, icon: category.icon, color: category.color,
            isRenamed: category.isRenamed, monthlyBudget: Money(amount, "USD"),
        ))
    }

    @Test
    func budgetsNearOrOverTheirLineAreAlertedOnceEachThisMonth() async throws {
        let store = InMemoryStore(sample: .standard)
        let month = try #require(await loadedViewModel(store).overview?.month)
        let spent = try #require(month.categories.first)
        let quiet = try #require(TransactionCategory.defaultExpense.first { id in
            !month.categories.contains { $0.categoryID == id.id }
        })
        try await budgeting(store, spent.categoryID, spent.amount)
        try await budgeting(store, quiet.id, 100)

        let viewModel = await loadedViewModel(store)
        let alerts = viewModel.budgetAlerts
        #expect(alerts.map(\.categoryID) == [spent.categoryID])
        #expect(alerts.first?.level == .exceeded)
        #expect(alerts.first?.title.hasSuffix("went over its budget") == true)
        #expect(alerts.first?.body.hasSuffix("this month.") == true)

        let budgetMonth = try #require(viewModel.overview?.month.month)
        let monthKey = String(format: "%04d-%02d", budgetMonth.year, budgetMonth.month)
        let reminders = viewModel.reminders(now: now).filter { $0.kind == .budget }
        #expect(reminders.map(\.id) == ["budget:\(spent.categoryID):\(monthKey):over"])
        #expect(reminders.allSatisfy { $0.isOneShot && $0.target == ["screen": "summary"] })

        try await budgeting(store, spent.categoryID, spent.amount / #require(Decimal(string: "0.85")))
        let near = await loadedViewModel(store)
        #expect(near.budgetAlerts.first?.level == .nearLimit)
        #expect(near.budgetAlerts.first?.title.hasSuffix("is close to its budget") == true)
        #expect(near.reminders(now: now).first { $0.kind == .budget }?.id == "budget:\(spent.categoryID):\(monthKey):near")
    }

    @Test
    func noBudgetsMeansNoAlerts() async {
        let viewModel = await loadedViewModel()
        #expect(viewModel.budgetAlerts.isEmpty)
        #expect(!viewModel.reminders(now: now).contains { $0.kind == .budget })
    }
}
