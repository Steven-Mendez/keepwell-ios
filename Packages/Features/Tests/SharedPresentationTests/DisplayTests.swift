import Core
import Domain
import Foundation
import Testing
@testable import SharedPresentation

@Suite("Display mappings")
struct DisplayTests {
    @Test
    func cardNamesAndWordmarks() throws {
        let account = Account(name: "Ahorro", bank: "Banco Uno", kind: .deposit, openingBalances: [Money(0, "USD")], openingDate: .now)
        let debit = try Card(accountID: account.id, kind: .debit, network: .visa, lastFour: "1234", color: .coral)
        let transfer = try Card(accountID: account.id, kind: .transfer)
        #expect(CardDisplay.name(of: account) == "Banco Uno Ahorro")
        #expect(CardDisplay.methodTitle(debit, account: account) == "Débito •••• 1234")
        #expect(CardDisplay.methodTitle(transfer, account: account) == "Transferencias Banco Uno")
        #expect(CardDisplay.shortName(of: debit) == "Visa ··1234")
        #expect(CardDisplay.wordmark(for: .mastercard) == "mastercard")
        #expect(CardDisplay.palette(for: .lima) == .lima)
        #expect(CardDisplay.cardColor(for: .oro) == .oro)
    }

    @Test
    func joinedBalancesLikeTheCards() {
        let formatter = CurrencyFormatter()
        let text = formatter.joined([Money(Decimal(string: "-197.02") ?? 0, "NIO"), Money(Decimal(string: "-16.79") ?? 0, "USD")])
        #expect(text == "−C$197.02 · −$16.79")
    }
}
