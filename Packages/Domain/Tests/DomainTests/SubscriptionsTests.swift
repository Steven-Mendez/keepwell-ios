import Foundation
import Testing
@testable import Domain

@Suite("Subscriptions")
struct SubscriptionsTests {
    private let card = UUID()
    private let account = UUID()
    private let calendar = Calendar(identifier: .gregorian)

    private func charge(
        _ description: String,
        on day: String,
        category: String = "tools",
        card: UUID? = nil,
        status: TransactionStatus = .confirmed,
    ) throws -> Transaction {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        let date = try #require(calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)))
        return Transaction(
            date: date,
            status: status,
            description: description,
            kind: .expense,
            categoryID: category,
            amount: 10,
            currency: "USD",
            accountID: account,
            cardID: card ?? self.card,
            exchangeRate: .single("USD"),
        )
    }

    @Test
    func repeatedMonthlyChargesAndTheSubscriptionsCategoryCount() throws {
        let transactions = try [
            charge("OpenAI", on: "2026-09-30"),
            charge("openai ", on: "2026-10-20"),
            charge("Apple Music", on: "2026-10-01", category: Subscriptions.categoryID),
            charge("Amazon Digital", on: "2026-10-28"),
            charge("Higgsfield", on: "2026-10-10"),
            charge("Higgsfield", on: "2026-10-11"),
        ]
        let found = Subscriptions.charged(toCard: card, transactions: transactions, calendar: calendar)
        #expect(found == ["openai ", "Apple Music"])
    }

    @Test
    func otherCardsAndPlannedChargesDontCount() throws {
        let transactions = try [
            charge("Netflix", on: "2026-09-05", category: Subscriptions.categoryID, card: UUID()),
            charge("Spotify", on: "2026-11-05", category: Subscriptions.categoryID, status: .planned),
        ]
        #expect(Subscriptions.charged(toCard: card, transactions: transactions, calendar: calendar).isEmpty)
    }
}
