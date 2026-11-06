import Foundation
import Testing
@testable import Domain

/// Mirrored by keepwell-web `tests/domain/forecast.test.ts` ("Price increases").
@Suite("Price increases")
struct PriceIncreaseTests {
    private let calendar = Fixtures.calendar
    private let now = Fixtures.date(2026, 11, 6)
    private let card = UUID()

    private func charge(
        _ description: String,
        _ amount: String,
        on date: Date,
        currency: String = "USD",
        category: String = "tools",
        card: UUID? = nil,
        rule: UUID? = nil,
        status: TransactionStatus = .confirmed,
    ) -> Transaction {
        Transaction(
            date: date, status: status, description: description, kind: .expense, categoryID: category,
            amount: Fixtures.decimal(amount), currency: currency, accountID: UUID(), cardID: card ?? self.card,
            exchangeRate: .single(currency), recurringID: rule,
        )
    }

    @Test
    func findsServicesWhoseNewestChargeCostsMore() {
        let rule = UUID()
        let transactions = [
            // A rule's charges, whatever their description or card.
            charge("Gym", "30", on: Fixtures.date(2026, 9, 10), card: UUID(), rule: rule),
            charge("Gym club", "35", on: Fixtures.date(2026, 10, 10), rule: rule),
            // Recognized by the card and description: two months.
            charge("Netflix", "9.99", on: Fixtures.date(2026, 9, 20)),
            charge("netflix ", "12.99", on: Fixtures.date(2026, 10, 20)),
            // In the Subscriptions category: cheaper now.
            charge("Spotify", "11", on: Fixtures.date(2026, 9, 1), category: Subscriptions.categoryID),
            charge("Spotify", "10", on: Fixtures.date(2026, 10, 1), category: Subscriptions.categoryID),
            // Currencies differ.
            charge("iCloud", "1", on: Fixtures.date(2026, 9, 15)),
            charge("iCloud", "40", on: Fixtures.date(2026, 10, 15), currency: "NIO"),
            // Went up, but too long ago.
            charge("Dropbox", "10", on: Fixtures.date(2026, 8, 1)),
            charge("Dropbox", "12", on: Fixtures.date(2026, 9, 1)),
            // A draft doesn't count.
            charge("Disney", "8", on: Fixtures.date(2026, 9, 25)),
            charge("Disney", "8", on: Fixtures.date(2026, 10, 25)),
            charge("Disney", "11", on: Fixtures.date(2026, 11, 25), status: .planned),
            // Same month, one-off purchases on the same card aren't a service.
            charge("Hardware store", "5", on: Fixtures.date(2026, 10, 10)),
            charge("Hardware store", "50", on: Fixtures.date(2026, 10, 11)),
        ]
        let found = PriceIncrease.detect(in: transactions, now: now, calendar: calendar)
        #expect(found.map(\.name) == ["netflix ", "Gym club"])
        #expect(found.first?.previous == Money(Fixtures.decimal("9.99"), "USD"))
        #expect(found.first?.current == Money(Fixtures.decimal("12.99"), "USD"))
        #expect(found.last?.previous == Money(30, "USD"))
    }
}
