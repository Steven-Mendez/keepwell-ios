import Foundation
import Testing
@testable import Domain

@Suite("Recurring schedule")
struct RecurringScheduleTests {
    private let calendar = Fixtures.calendar
    private let account = UUID()

    private func rule(
        _ frequency: RecurringFrequency = .monthly,
        interval: Int = 1,
        start: Date = Fixtures.date(2026, 1, 31, hour: 9),
        next: Date? = nil,
        end: Date? = nil,
        amount: String = "10",
        autoConfirm: Bool = false,
        isPaused: Bool = false,
    ) -> RecurringRule {
        RecurringRule(
            name: "Gym",
            kind: .expense,
            categoryID: "health",
            amount: Fixtures.decimal(amount),
            currency: "USD",
            accountID: account,
            frequency: frequency,
            interval: interval,
            startDate: start,
            nextDate: next,
            endDate: end,
            autoConfirm: autoConfirm,
            isPaused: isPaused,
        )
    }

    private func day(_ date: Date?) -> DateComponents? {
        date.map { calendar.dateComponents([.year, .month, .day, .hour], from: $0) }
    }

    private func ymd(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> DateComponents {
        DateComponents(year: year, month: month, day: day, hour: hour)
    }

    // MARK: Occurrences

    @Test
    func monthlyOccurrencesClampFromTheAnchorAndNeverDrift() {
        let monthly = rule()
        #expect(day(RecurringSchedule.occurrence(of: monthly, 1, calendar: calendar)) == ymd(2026, 2, 28))
        #expect(day(RecurringSchedule.occurrence(of: monthly, 2, calendar: calendar)) == ymd(2026, 3, 31))
        #expect(day(RecurringSchedule.occurrence(of: monthly, 3, calendar: calendar)) == ymd(2026, 4, 30))
    }

    @Test
    func leapYearsAndYearlyRulesClampToo() {
        let leap = rule(start: Fixtures.date(2028, 1, 31, hour: 9))
        #expect(day(RecurringSchedule.occurrence(of: leap, 1, calendar: calendar)) == ymd(2028, 2, 29))
        let yearly = rule(.yearly, start: Fixtures.date(2028, 2, 29, hour: 9))
        #expect(day(RecurringSchedule.occurrence(of: yearly, 1, calendar: calendar)) == ymd(2029, 2, 28))
        #expect(day(RecurringSchedule.occurrence(of: yearly, 4, calendar: calendar)) == ymd(2032, 2, 29))
    }

    @Test
    func weeklyIsSevenDaysTimesTheInterval() {
        let biweekly = rule(.weekly, interval: 2, start: Fixtures.date(2026, 10, 1, hour: 9))
        #expect(day(RecurringSchedule.occurrence(of: biweekly, 1, calendar: calendar)) == ymd(2026, 10, 15))
        #expect(day(RecurringSchedule.occurrence(of: biweekly, 3, calendar: calendar)) == ymd(2026, 11, 12))
    }

    @Test
    func firstOccurrenceOnOrAfterADayComparesCalendarDays() {
        let monthly = rule()
        // Later in the same day still counts as that day.
        let sameDay = RecurringSchedule.firstOccurrence(of: monthly, onOrAfter: Fixtures.date(2026, 3, 31, hour: 23), calendar: calendar)
        #expect(day(sameDay) == ymd(2026, 3, 31))
        let after = RecurringSchedule.firstOccurrence(of: monthly, after: Fixtures.date(2026, 3, 31, hour: 8), calendar: calendar)
        #expect(day(after) == ymd(2026, 4, 30))
        let beforeStart = RecurringSchedule.firstOccurrence(of: monthly, onOrAfter: Fixtures.date(2025, 6, 1), calendar: calendar)
        #expect(day(beforeStart) == ymd(2026, 1, 31))
        let farAway = RecurringSchedule.firstOccurrence(of: monthly, onOrAfter: Fixtures.date(2036, 2, 1), calendar: calendar)
        #expect(day(farAway) == ymd(2036, 2, 29))
    }

    // MARK: Due

    @Test
    func dueRunsFromNextDateThroughTodayAndStopsAtTheEnd() {
        let monthly = rule(next: Fixtures.date(2026, 2, 28, hour: 9), end: Fixtures.date(2026, 4, 30, hour: 0))
        let due = RecurringSchedule.due(monthly, today: Fixtures.date(2026, 6, 15), calendar: calendar)
        #expect(due.map(day) == [ymd(2026, 2, 28), ymd(2026, 3, 31), ymd(2026, 4, 30)])
    }

    @Test
    func pausedRulesHaveNothingDue() {
        let paused = rule(isPaused: true)
        #expect(RecurringSchedule.due(paused, today: Fixtures.date(2026, 6, 15), calendar: calendar).isEmpty)
    }

    // MARK: Materialize

    @Test
    func materializeRecordsDraftsWithTodaysRateAndMovesTheRuleOn() throws {
        let monthly = rule(start: Fixtures.date(2026, 10, 5, hour: 9))
        let result = RecurringSchedule.materialize(
            [monthly], transactions: [], today: Fixtures.date(2026, 11, 6), exchangeRate: Fixtures.usdNio, calendar: calendar,
        )
        #expect(result.transactions.count == 2)
        let first = try #require(result.transactions.first)
        #expect(first.status == .planned)
        #expect(first.recurringID == monthly.id)
        #expect(first.description == "Gym")
        #expect(first.exchangeRate == Fixtures.usdNio)
        #expect(first.isShared == false)
        #expect(day(first.date) == ymd(2026, 10, 5))
        #expect(result.rules.map { day($0.nextDate) } == [ymd(2026, 12, 5)])
    }

    @Test
    func autoConfirmedRulesRecordConfirmedMovements() {
        let monthly = rule(start: Fixtures.date(2026, 11, 1, hour: 9), autoConfirm: true)
        let result = RecurringSchedule.materialize(
            [monthly], transactions: [], today: Fixtures.date(2026, 11, 6), exchangeRate: Fixtures.usdNio, calendar: calendar,
        )
        #expect(result.transactions.map(\.status) == [.confirmed])
    }

    @Test
    func afterMonthsAwayOnlyTheLatestTwelveAreRecorded() {
        let weekly = rule(.weekly, start: Fixtures.date(2026, 1, 1, hour: 9))
        let result = RecurringSchedule.materialize(
            [weekly], transactions: [], today: Fixtures.date(2026, 12, 31), exchangeRate: Fixtures.usdNio, calendar: calendar,
        )
        #expect(result.transactions.count == RecurringSchedule.catchUpLimit)
        #expect(day(result.transactions.last?.date) == ymd(2026, 12, 31))
        #expect(day(result.rules.first?.nextDate) == ymd(2027, 1, 7))
    }

    @Test
    func anOccurrenceAlreadyRecordedOnThatDayIsSkipped() {
        let monthly = rule(start: Fixtures.date(2026, 10, 5, hour: 9))
        // Another device already recorded October, at another time of the same day.
        let recorded = RecurringSchedule.movement(from: monthly, on: Fixtures.date(2026, 10, 5, hour: 20), exchangeRate: Fixtures.usdNio)
        let result = RecurringSchedule.materialize(
            [monthly], transactions: [recorded], today: Fixtures.date(2026, 11, 6), exchangeRate: Fixtures.usdNio, calendar: calendar,
        )
        #expect(result.transactions.map { day($0.date) } == [ymd(2026, 11, 5)])
    }

    @Test
    func runningTwiceRecordsNothingNew() {
        let monthly = rule(start: Fixtures.date(2026, 10, 5, hour: 9))
        let today = Fixtures.date(2026, 11, 6)
        let first = RecurringSchedule.materialize(
            [monthly],
            transactions: [],
            today: today,
            exchangeRate: Fixtures.usdNio,
            calendar: calendar,
        )
        // A device that synced the movements but not the rule's new `nextDate`.
        let second = RecurringSchedule.materialize(
            [monthly], transactions: first.transactions, today: today, exchangeRate: Fixtures.usdNio, calendar: calendar,
        )
        #expect(second.transactions.isEmpty)
        #expect(second.rules.map { day($0.nextDate) } == [ymd(2026, 12, 5)])
        let third = RecurringSchedule.materialize(
            first.rules, transactions: first.transactions, today: today, exchangeRate: Fixtures.usdNio, calendar: calendar,
        )
        #expect(third.isEmpty)
    }

    @Test
    func aTrailingOccurrenceAlreadyRecordedIsNotOwedAgain() {
        let monthly = rule(start: Fixtures.date(2026, 10, 5, hour: 9))
        // November is already on the ledger, October is not: the rule must still move past November.
        let recorded = RecurringSchedule.movement(from: monthly, on: Fixtures.date(2026, 11, 5, hour: 9), exchangeRate: Fixtures.usdNio)
        let result = RecurringSchedule.materialize(
            [monthly], transactions: [recorded], today: Fixtures.date(2026, 11, 6), exchangeRate: Fixtures.usdNio, calendar: calendar,
        )
        #expect(result.transactions.map { day($0.date) } == [ymd(2026, 10, 5)])
        #expect(result.rules.map { day($0.nextDate) } == [ymd(2026, 12, 5)])
    }

    @Test
    func aRuleIsFinishedOnceItsNextOccurrenceIsPastItsEnd() {
        let live = rule(start: Fixtures.date(2026, 10, 5, hour: 9), end: Fixtures.date(2026, 12, 31))
        let done = rule(
            start: Fixtures.date(2026, 10, 5, hour: 9),
            next: Fixtures.date(2027, 1, 5, hour: 9),
            end: Fixtures.date(2026, 12, 31),
        )
        #expect(RecurringSchedule.isActive(live, calendar: calendar))
        #expect(RecurringSchedule.isFinished(done, calendar: calendar))
        #expect(!RecurringSchedule.isActive(done, calendar: calendar))
        #expect(!RecurringSchedule.isActive(rule(isPaused: true), calendar: calendar))
    }

    @Test
    func pausedRulesRecordNothingAndKeepTheirNextDate() {
        let paused = rule(start: Fixtures.date(2026, 10, 5, hour: 9), isPaused: true)
        let result = RecurringSchedule.materialize(
            [paused], transactions: [], today: Fixtures.date(2026, 11, 6), exchangeRate: Fixtures.usdNio, calendar: calendar,
        )
        #expect(result.isEmpty)
    }

    @Test
    func resumingStartsFromTodayWithoutBackfilling() throws {
        let paused = rule(start: Fixtures.date(2026, 1, 5, hour: 9), next: Fixtures.date(2026, 3, 5, hour: 9), isPaused: true)
        let today = Fixtures.date(2026, 11, 6)
        let next = try #require(RecurringSchedule.firstOccurrence(of: paused, onOrAfter: today, calendar: calendar))
        let resumed = paused.with(isPaused: false, nextDate: next)
        let result = RecurringSchedule.materialize(
            [resumed],
            transactions: [],
            today: today,
            exchangeRate: Fixtures.usdNio,
            calendar: calendar,
        )
        #expect(day(next) == ymd(2026, 12, 5))
        #expect(result.isEmpty)
    }

    @Test
    func reschedulingStartsFromTodayOrTheStartWhicheverIsLater() {
        let today = Fixtures.date(2026, 11, 6)
        let past = rule(start: Fixtures.date(2026, 1, 10, hour: 9))
        #expect(day(RecurringSchedule.rescheduledNextDate(of: past, today: today, calendar: calendar)) == ymd(2026, 11, 10))
        let future = rule(start: Fixtures.date(2027, 2, 1, hour: 9))
        #expect(day(RecurringSchedule.rescheduledNextDate(of: future, today: today, calendar: calendar)) == ymd(2027, 2, 1))
    }

    // MARK: Upcoming and totals

    @Test
    func upcomingListsTheNextDaysSoonestFirst() {
        let today = Fixtures.date(2026, 11, 6)
        let weekly = rule(.weekly, start: Fixtures.date(2026, 11, 6, hour: 9))
        let monthly = rule(start: Fixtures.date(2026, 10, 8, hour: 9), next: Fixtures.date(2026, 11, 8, hour: 9))
        let paused = rule(start: Fixtures.date(2026, 11, 7, hour: 9), isPaused: true)
        let upcoming = RecurringSchedule.upcoming([monthly, weekly, paused], from: today, days: 7, calendar: calendar)
        #expect(upcoming.map { day($0.date) } == [ymd(2026, 11, 6), ymd(2026, 11, 8), ymd(2026, 11, 13)])
        #expect(upcoming.map(\.rule.id) == [weekly.id, monthly.id, weekly.id])
    }

    @Test
    func nextListsTheComingDatesWithinTheEnd() {
        let monthly = rule(start: Fixtures.date(2026, 11, 30, hour: 9), end: Fixtures.date(2027, 1, 31))
        #expect(RecurringSchedule.next(3, of: monthly, calendar: calendar).map(day) == [
            ymd(2026, 11, 30), ymd(2026, 12, 30), ymd(2027, 1, 30),
        ])
    }

    @Test
    func monthlyEquivalentPerFrequency() {
        #expect(RecurringSchedule.monthlyEquivalent(of: rule(.monthly, interval: 2, amount: "30")) == 15)
        #expect(RecurringSchedule.monthlyEquivalent(of: rule(.weekly, amount: "12")) == 52)
        #expect(RecurringSchedule.monthlyEquivalent(of: rule(.yearly, amount: "120")) == 10)
        #expect(RecurringSchedule.monthlyEquivalent(of: rule(.yearly, interval: 2, amount: "240")) == 10)
    }
}

@Suite("Recurring rule validation")
struct RecurringRuleValidationTests {
    private let calendar = Fixtures.calendar
    private let account = UUID()

    private func rule(
        interval: Int = 1,
        start: Date = Fixtures.date(2026, 1, 31, hour: 9),
        end: Date? = nil,
        amount: String = "10",
    ) -> RecurringRule {
        RecurringRule(
            name: "Gym", kind: .expense, categoryID: "health", amount: Fixtures.decimal(amount), currency: "USD",
            accountID: account, frequency: .monthly, interval: interval, startDate: start, endDate: end,
        )
    }

    @Test
    func aRuleChecksItsOwnLimits() {
        let today = Fixtures.date(2026, 11, 6)
        #expect(throws: DomainError.invalidAmount) { try rule(amount: "0").checkSchedule(calendar: calendar) }
        #expect(throws: DomainError.invalidInterval(0)) { try rule(interval: 0).checkSchedule(calendar: calendar) }
        #expect(throws: DomainError.invalidInterval(100)) { try rule(interval: 100).checkSchedule(calendar: calendar) }
        #expect(throws: DomainError.invalidEndDate) {
            try rule(start: today, end: Fixtures.date(2026, 11, 5)).checkSchedule(calendar: calendar)
        }
        // Ending on the start day, earlier in that day, is fine.
        #expect(throws: Never.self) {
            try rule(start: Fixtures.date(2026, 11, 6, hour: 18), end: Fixtures.date(2026, 11, 6, hour: 0))
                .checkSchedule(calendar: calendar)
        }
        let unnamed = RecurringRule(
            name: "  ", kind: .expense, categoryID: "health", amount: 1, currency: "USD", accountID: account,
            frequency: .monthly, startDate: today,
        )
        #expect(throws: DomainError.missingName) { try unnamed.checkSchedule(calendar: calendar) }
    }

    @Test
    func validationFollowsTheMovementRulesAndDerivesTheAccountFromTheCard() throws {
        let currencies = try CurrencySettings(principal: "USD", second: "NIO", rate: 36)
        let bank = Account(name: "Bank", kind: .deposit, openingBalances: [Money(0, "USD")], openingDate: .distantPast)
        let cash = Account(name: "Cash", kind: .cash, openingBalances: [Money(0, "NIO")], openingDate: .distantPast)
        let card = try Card(accountID: bank.id, kind: .debit)
        let categories = TransactionCategory.defaults
        let draft = RecurringRule(
            name: " Gym ", kind: .expense, categoryID: "health", amount: 10, currency: "NIO", accountID: UUID(),
            cardID: card.id, destinationAccountID: cash.id, frequency: .monthly, startDate: .now, note: "  ",
        )
        let valid = try draft.validated(
            currencies: currencies,
            accounts: [bank, cash],
            cards: [card],
            categories: categories,
            calendar: calendar,
        )
        #expect(valid.accountID == bank.id)
        #expect(valid.name == "Gym")
        #expect(valid.destinationAccountID == nil)
        #expect(valid.note == nil)

        let euros = RecurringRule(
            name: "Gym", kind: .expense, categoryID: "health", amount: 10, currency: "EUR", accountID: bank.id,
            frequency: .monthly, startDate: .now,
        )
        #expect(throws: DomainError.invalidCurrency("EUR")) {
            try euros.validated(currencies: currencies, accounts: [bank], cards: [], categories: categories, calendar: calendar)
        }
        let wrongCategory = RecurringRule(
            name: "Pay", kind: .income, categoryID: "health", amount: 10, currency: "USD", accountID: bank.id,
            frequency: .monthly, startDate: .now,
        )
        #expect(throws: DomainError.categoryKindMismatch(expected: .income, actual: .expense)) {
            try wrongCategory.validated(currencies: currencies, accounts: [bank], cards: [], categories: categories, calendar: calendar)
        }
        let toItself = RecurringRule(
            name: "Move", kind: .transfer, categoryID: "health", amount: 10, currency: "USD", accountID: bank.id,
            destinationAccountID: bank.id, frequency: .monthly, startDate: .now,
        )
        #expect(throws: DomainError.invalidTransferDestination) {
            try toItself.validated(currencies: currencies, accounts: [bank], cards: [], categories: categories, calendar: calendar)
        }
    }
}
