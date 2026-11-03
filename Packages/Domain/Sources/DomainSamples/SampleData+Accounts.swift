import Domain
import Foundation

extension SampleData {
    static func makeAccounts(opening: Date) -> [Account] {
        [
            Account(
                id: IDs.savings,
                name: "Ahorro",
                bank: "Banco Uno",
                kind: .deposit,
                openingBalances: [Money(9520, "USD")],
                openingDate: opening,
            ),
            Account(
                id: IDs.payroll,
                name: "Nómina",
                bank: "Banco Dos",
                kind: .deposit,
                openingBalances: [Money(Decimal(string: "-480.10") ?? 0, "USD")],
                openingDate: opening,
            ),
            Account(
                id: IDs.cash,
                name: "Billetera",
                kind: .cash,
                openingBalances: [Money(7500, "NIO")],
                openingDate: opening,
            ),
            Account(
                id: IDs.mastercard,
                name: "Mastercard",
                bank: "Banco Uno",
                kind: .credit,
                openingBalances: [Money(0, "USD"), Money(0, "NIO")],
                openingDate: opening,
                creditTerms: try? CreditTerms(debtMode: .dual),
            ),
            Account(
                id: IDs.visa,
                name: "Visa",
                bank: "Banco Dos",
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
        let additional = AdditionalCardControls(
            holderName: "Súper familiar",
            cycleCap: Money(4000, "NIO"),
            allowedCategoryIDs: ["groceries", "health"],
            defaultCategoryID: "groceries",
        )
        return [
            try? Card(id: IDs.savingsDebit, accountID: IDs.savings, kind: .debit, network: .visa, lastFour: "1234", color: .coral),
            try? Card(id: IDs.savingsTransfer, accountID: IDs.savings, kind: .transfer),
            try? Card(id: IDs.payrollDebit, accountID: IDs.payroll, kind: .debit, network: .visa, lastFour: "5678", color: .violeta),
            try? Card(id: IDs.payrollTransfer, accountID: IDs.payroll, kind: .transfer),
            try? Card(
                id: IDs.mastercardHolder, accountID: IDs.mastercard, kind: .creditHolder,
                network: .mastercard, lastFour: "4321", color: .azul,
            ),
            try? Card(
                id: IDs.mastercardAdditional, accountID: IDs.mastercard, kind: .creditAdditional,
                network: .mastercard, lastFour: "8765", color: .lima, additional: additional,
            ),
            try? Card(id: IDs.visaHolder, accountID: IDs.visa, kind: .creditHolder, network: .visa, lastFour: "9012", color: .grafito),
        ].compactMap(\.self)
    }
}
