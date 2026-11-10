import Domain
import DomainSamples
import Foundation
import Testing
@testable import SharedPresentation

@Suite("Movements recorded by an assistant")
struct AssistantLabelTests {
    @Test
    func saySoInTheirSubtitleAndOthersDont() throws {
        let sample = SampleData.standard
        let display = TransactionDisplay(accounts: sample.accounts, cards: sample.cards, categories: sample.categories)
        let movement = try #require(sample.transactions.first { $0.kind == .expense })
        let byClaude = Transaction(
            id: movement.id, date: movement.date, status: .planned, description: movement.description, kind: movement.kind,
            categoryID: movement.categoryID, amount: movement.amount, currency: movement.currency, accountID: movement.accountID,
            cardID: movement.cardID, exchangeRate: movement.exchangeRate, source: .mcp,
        )
        #expect(display.subtitle(of: byClaude).hasPrefix("Recorded by Claude"))
        #expect(!display.subtitle(of: movement).contains("Claude"))
        #expect(byClaude.confirmed().source == .mcp)
    }
}
