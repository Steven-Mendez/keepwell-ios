import Domain
import Foundation

extension SampleData {
    static func makeAccounts(opening: Date, language: SampleLanguage) -> [Account] {
        [
            Account(
                id: IDs.savings,
                name: text("Savings", language),
                bank: text("Bank One", language),
                kind: .deposit,
                openingBalances: [Money(9520, "USD")],
                openingDate: opening,
            ),
            Account(
                id: IDs.payroll,
                name: text("Payroll", language),
                bank: text("Bank Two", language),
                kind: .deposit,
                openingBalances: [Money(Decimal(string: "-480.10") ?? 0, "USD")],
                openingDate: opening,
            ),
            Account(
                id: IDs.cash,
                name: text("Wallet", language),
                kind: .cash,
                openingBalances: [Money(7500, "NIO")],
                openingDate: opening,
            ),
            Account(
                id: IDs.mastercard,
                name: "Mastercard",
                bank: text("Bank One", language),
                kind: .credit,
                openingBalances: [Money(0, "USD"), Money(0, "NIO")],
                openingDate: opening,
                creditTerms: try? CreditTerms(debtMode: .dual),
            ),
            Account(
                id: IDs.visa,
                name: "Visa",
                bank: text("Bank Two", language),
                kind: .credit,
                openingBalances: [Money(-880, "NIO")],
                openingDate: opening,
                creditTerms: try? CreditTerms(debtMode: .second, cutoffDay: 28, dueDay: 15),
            ),
        ]
    }

    static let fallbackCurrencies: CurrencySettings = {
        guard let settings = try? CurrencySettings() else { preconditionFailure("Default currency settings are valid") }
        return settings
    }()

    static func makeCards() -> [Card] {
        [
            try? Card(id: IDs.savingsDebit, accountID: IDs.savings, kind: .debit, network: .visa, lastFour: "1234", color: .verde),
            try? Card(id: IDs.savingsTransfer, accountID: IDs.savings, kind: .transfer),
            try? Card(id: IDs.payrollDebit, accountID: IDs.payroll, kind: .debit, network: .visa, lastFour: "5678", color: .platino),
            try? Card(id: IDs.payrollTransfer, accountID: IDs.payroll, kind: .transfer),
            try? Card(
                id: IDs.mastercardHolder, accountID: IDs.mastercard, kind: .creditHolder,
                network: .mastercard, lastFour: "4321", color: .azul,
            ),
            try? Card(id: IDs.visaHolder, accountID: IDs.visa, kind: .creditHolder, network: .visa, lastFour: "9012", color: .grafito),
        ].compactMap(\.self)
    }
}
