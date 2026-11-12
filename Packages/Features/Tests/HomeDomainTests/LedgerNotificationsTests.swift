import Domain
import DomainSamples
import Foundation
import Testing
@testable import HomeDomain

/// Which notifications apply on a day and what their ids are, the same cases as keepwell-web's
/// `tests/notifications.test.ts` so both apps name an occurrence the same way.
@Suite("Ledger notifications")
struct LedgerNotificationsTests {
    private let calendar = Calendar.current

    private func date(_ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .now
    }

    private func overview(
        _ store: InMemoryStore = InMemoryStore(sample: .standard),
        now: Date,
    ) async throws -> HomeOverview {
        try await DefaultGetHomeOverviewUseCase(
            accounts: store, cards: store, transactions: store, categories: store, settings: store,
            recurringRules: store, loans: store, calendar: calendar, now: { now },
        ).execute()
    }

    private var visa: String {
        SampleData.IDs.visa.uuidString.lowercased()
    }

    @Test
    func eachCardPaymentIsNamedByItsDueDaySoNextMonthsIsANewNotification() async throws {
        // The sample's Visa is due on the 15th.
        let november = date(11, 13)
        let december = date(12, 13)
        let first = try await LedgerNotifications.applying(on: november, in: overview(now: november), calendar: calendar)
        let second = try await LedgerNotifications.applying(on: december, in: overview(now: december), calendar: calendar)
        #expect(first.first { $0.kind == .payment }?.id == "payment:\(visa):2026-11-15")
        #expect(second.first { $0.kind == .payment }?.id == "payment:\(visa):2026-12-15")
    }

    @Test
    func idsDontChangeAcrossTheHoursOfADay() async throws {
        let overview = try await overview(now: date(11, 13))
        let ids = { (now: Date) in LedgerNotifications.applying(on: now, in: overview, calendar: calendar).map(\.id).sorted() }
        #expect(try ids(date(11, 13, hour: 0, minute: 5)) == ids(date(11, 13, hour: 23, minute: 55)))
    }

    @Test
    func idsUseLowercaseUUIDs() async throws {
        let now = date(11, 13)
        let all = try await LedgerNotifications.applying(on: now, in: overview(now: now), calendar: calendar)
        #expect(!all.isEmpty)
        #expect(all.allSatisfy { $0.id == $0.id.lowercased() || $0.kind == .budget })
    }

    @Test
    func aPaymentAppliesFromTheReminderWindowThroughItsDueDay() async throws {
        let overview = try await overview(now: date(11, 11))
        // Three days before the 15th it starts; the day before that, nothing.
        #expect(try !LedgerNotifications.applying(on: date(11, 11), in: overview, calendar: calendar).contains { $0.kind == .payment })
        let start = try LedgerNotifications.applying(on: date(11, 12), in: overview, calendar: calendar)
        let payment = try #require(start.first { $0.kind == .payment })
        #expect(payment.date == calendar.startOfDay(for: date(11, 12)))
        #expect(payment.target == .creditCard(accountID: SampleData.IDs.visa))
        #expect(try LedgerNotifications.applying(on: date(11, 15), in: overview, calendar: calendar).contains { $0.kind == .payment })
    }

    @Test
    func aStatementClosingTodayAppliesOnlyThatDay() async throws {
        // The sample's Visa closes on the 28th.
        let overview = try await overview(now: date(10, 27))
        let closing = try LedgerNotifications.applying(on: date(10, 28), in: overview, calendar: calendar)
        #expect(closing.first { $0.kind == .cutoff }?.id == "cutoff:\(visa):2026-10-28")
        #expect(try !LedgerNotifications.applying(on: date(10, 27), in: overview, calendar: calendar).contains { $0.kind == .cutoff })
        #expect(try !LedgerNotifications.applying(on: date(10, 29), in: overview, calendar: calendar).contains { $0.kind == .cutoff })
    }

    @Test
    func aLoansNextInstallmentIsNamedByItsNumberAndAppliesInsideTheWindow() async throws {
        // The sample's motorbike loan owes installment 3 on 28 October.
        let overview = try await overview(now: date(10, 22))
        let loan = SampleData.IDs.motorbikeLoan.uuidString.lowercased()
        #expect(try LedgerNotifications.applying(on: date(10, 22), in: overview, calendar: calendar)
            .contains { $0.kind == .installment } == false)
        let inside = try LedgerNotifications.applying(on: date(10, 26), in: overview, calendar: calendar)
        #expect(inside.first { $0.kind == .installment }?.id == "installment:\(loan):3")
        #expect(inside.first { $0.kind == .installment }?.target == .debts)
    }

    @Test
    func aSubscriptionRenewingTomorrowIsNamedByTheOccurrenceDay() async throws {
        let now = SampleData.defaultReferenceDate
        let overview = try await overview(now: now)
        let renewal = try #require(LedgerNotifications.applying(on: now, in: overview, calendar: calendar).first { $0.kind == .renewal })
        let rule = SampleData.IDs.streamingRule.uuidString.lowercased()
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)))
        #expect(renewal.id == "renewal:\(rule):\(LedgerNotifications.dayKey(tomorrow, calendar: calendar))")
        #expect(renewal.target == .recurring)
    }

    @Test
    func draftsDatedTodayOrBeforeApplyAndLaterOnesDontYet() async throws {
        let now = SampleData.defaultReferenceDate
        let overview = try await overview(now: now)
        let planned = LedgerNotifications.applying(on: now, in: overview, calendar: calendar).filter { $0.kind == .planned }
        #expect(planned.allSatisfy { $0.id.hasPrefix("planned:") })
        let due = overview.planned.filter { calendar.startOfDay(for: $0.date) <= calendar.startOfDay(for: now) }
        #expect(planned.count == due.count)
    }

    @Test
    func onlyPausedAssistantProposalsAreListed() async throws {
        let now = date(10, 25)
        let store = InMemoryStore(sample: .standard)
        let proposed = RecurringRule(
            name: "Gym", kind: .expense, categoryID: "health", amount: 30, currency: "USD", accountID: SampleData.IDs.savings,
            frequency: .monthly, startDate: now, isPaused: true, source: .mcp,
        )
        await store.save(proposed)
        await store.save(RecurringRule(
            name: "Running", kind: .expense, categoryID: "health", amount: 30, currency: "USD", accountID: SampleData.IDs.savings,
            frequency: .monthly, startDate: now, isPaused: false, source: .mcp,
        ))
        await store.save(RecurringRule(
            name: "Mine", kind: .expense, categoryID: "health", amount: 30, currency: "USD", accountID: SampleData.IDs.savings,
            frequency: .monthly, startDate: now, isPaused: true, source: .app,
        ))
        let overview = try await overview(store, now: now)
        let ids = LedgerNotifications.applying(on: now, in: overview, calendar: calendar).filter { $0.kind == .proposal }.map(\.id)
        #expect(ids == ["proposal:\(proposed.id.uuidString.lowercased())"])
    }

    @Test
    func budgetsCarryTheirLevelInTheIdAndAreDatedByTheLatestSpending() async throws {
        let now = SampleData.defaultReferenceDate
        let store = InMemoryStore(sample: .standard)
        let first = try #require(try await overview(store, now: now).month.categories.first)
        let category = try #require(await store.fetchCategories().first { $0.id == first.categoryID })
        await store.save(TransactionCategory(
            id: category.id, name: category.name, kind: category.kind, icon: category.icon, color: category.color,
            isRenamed: category.isRenamed, monthlyBudget: Money(first.amount, "USD"),
        ))
        let overview = try await overview(store, now: now)
        let budget = try #require(LedgerNotifications.applying(on: now, in: overview, calendar: calendar).first { $0.kind == .budget })
        #expect(budget.id == "budget:\(first.categoryID):2026-10:over")
        #expect(budget.target == .summary)
        #expect(budget.date == overview.latestExpenseDays[first.categoryID].map(calendar.startOfDay(for:)))
    }

    @Test
    func newestComeFirst() async throws {
        let now = SampleData.defaultReferenceDate
        let all = try await LedgerNotifications.applying(on: now, in: overview(now: now), calendar: calendar)
        #expect(all.map(\.date) == all.map(\.date).sorted(by: >))
    }

    // MARK: - Schedule

    @Test
    func theScheduleHasEachIdOnceAndOnlyInTheFuture() async throws {
        let now = SampleData.defaultReferenceDate
        let scheduled = try await LedgerNotifications.schedule(from: now, in: overview(now: now), calendar: calendar)
        #expect(Set(scheduled.map(\.notification.id)).count == scheduled.count)
        #expect(scheduled.filter { !$0.notification.isOneShot }.allSatisfy { $0.fireDate > now })
        #expect(scheduled.allSatisfy { $0.fireDate >= now })
    }

    @Test
    func aPaymentIsScheduledForTheMorningItFirstApplies() async throws {
        let now = SampleData.defaultReferenceDate
        let scheduled = try await LedgerNotifications.schedule(from: now, in: overview(now: now), calendar: calendar)
        let payment = try #require(scheduled.first { $0.notification.id == "payment:\(visa):2026-11-15" })
        let parts = calendar.dateComponents([.month, .day, .hour], from: payment.fireDate)
        #expect(parts.month == 11)
        #expect(parts.day == 12)
        #expect(parts.hour == LedgerNotifications.reminderHour)
        guard case let .payment(_, _, _, daysLeft) = payment.notification.subject else {
            Issue.record("Not a payment")
            return
        }
        #expect(daysLeft == 3)
    }

    @Test
    func aPaymentTheMorningHasPassedIsScheduledForTomorrowWorded() async throws {
        // 13 Nov 10:00: the 12th's morning is gone, the 14th's is the next that applies (1 day left).
        let now = date(11, 13, hour: 10)
        let scheduled = try await LedgerNotifications.schedule(from: now, in: overview(now: now), calendar: calendar)
        let payment = try #require(scheduled.first { $0.notification.kind == .payment })
        #expect(calendar.component(.day, from: payment.fireDate) == 14)
        guard case let .payment(_, _, _, daysLeft) = payment.notification.subject else {
            Issue.record("Not a payment")
            return
        }
        #expect(daysLeft == 1)
    }

    @Test
    func oneShotsThatAlreadyApplyComeRightAway() async throws {
        let now = date(10, 25)
        let store = InMemoryStore(sample: .standard)
        await store.save(RecurringRule(
            name: "Gym", kind: .expense, categoryID: "health", amount: 30, currency: "USD", accountID: SampleData.IDs.savings,
            frequency: .monthly, startDate: now, isPaused: true, source: .mcp,
        ))
        let scheduled = try await LedgerNotifications.schedule(from: now, in: overview(store, now: now), calendar: calendar)
        let proposal = try #require(scheduled.first { $0.notification.kind == .proposal })
        #expect(proposal.fireDate == now)
    }
}

@Suite("Notification payloads")
struct NotificationPayloadTests {
    private let account = SampleData.IDs.visa

    @Test
    func aTargetRoundTripsThroughItsJSON() {
        let targets: [LedgerNotification.Target] = [
            .transaction(SampleData.IDs.visa), .creditCard(accountID: account), .account(id: account), .debts, .recurring, .summary,
        ]
        for target in targets {
            #expect(LedgerNotification.Target(json: target.json) == target)
        }
        #expect(LedgerNotification.Target.creditCard(accountID: account).json == [
            "screen": "creditCard", "accountId": account.uuidString.lowercased(),
        ])
    }

    @Test
    func aPushCarriesItsTargetAsAnObjectOrAsText() {
        let object: [AnyHashable: Any] = ["target": ["screen": "debts"], "notification_id": "installment:x:3"]
        let text: [AnyHashable: Any] = ["target": #"{"screen":"account","accountId":"\#(account.uuidString)"}"#]
        #expect(LedgerNotification.Target(userInfo: object) == .debts)
        #expect(LedgerNotification.Target(userInfo: text) == .account(id: account))
        #expect(LedgerNotification.id(in: object) == "installment:x:3")
        #expect(LedgerNotification.Target(userInfo: ["target": ["screen": "nowhere"]]) == nil)
        #expect(LedgerNotification.Target(userInfo: [:]) == nil)
        #expect(LedgerNotification.id(in: [:]) == nil)
    }
}
