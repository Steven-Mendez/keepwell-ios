import Domain
import DomainSamples
import Foundation
import Testing
@testable import AddCardDomain

@Suite("Add card use cases")
struct AddCardUseCasesTests {
    private let store = InMemoryStore(sample: .standard)

    private func draft(_ mode: DebtMode = .dual) -> CreditCardDraft {
        CreditCardDraft(
            bank: "Banco Tres", lastFour: "2468", network: .mastercard, color: .violeta, debtMode: mode,
            principalDebt: 10, secondDebt: 250, limit: 1500, cutoffDay: 28, dueDay: 15,
        )
    }

    @Test
    func creditCardIsItsOwnAccountWithNegativeDebts() async throws {
        let (account, holder) = try await DefaultAddCreditCardUseCase(accounts: store, cards: store, settings: store).execute(draft())
        #expect(account.kind == .credit)
        #expect(account.openingBalances == [Money(-10, "USD"), Money(-250, "NIO")])
        #expect(try account.creditTerms == CreditTerms(debtMode: .dual, limit: Money(1500, "USD"), cutoffDay: 28, dueDay: 15))
        #expect(account.bank == "Banco Tres")
        #expect(holder.kind == .creditHolder)
        #expect(holder.accountID == account.id)
        #expect(await store.fetchCards().contains(holder))
    }

    @Test
    func secondCurrencyModeKeepsOneDebtInTheSecondCurrency() async throws {
        let (account, _) = try await DefaultAddCreditCardUseCase(accounts: store, cards: store, settings: store).execute(draft(.second))
        #expect(account.openingBalances == [Money(-10, "NIO")])
        #expect(account.creditTerms?.limit == Money(1500, "NIO"))
    }

    @Test
    func invalidDigitsAndAmountsAreRejected() async {
        var bad = draft()
        bad.lastFour = "12"
        let useCase = DefaultAddCreditCardUseCase(accounts: store, cards: store, settings: store)
        await #expect(throws: DomainError.invalidLastFour("12")) { _ = try await useCase.execute(bad) }
        var negative = draft()
        negative.principalDebt = -1
        await #expect(throws: DomainError.invalidAmount) { _ = try await useCase.execute(negative) }
    }

    @Test
    func debitCardLinksToABankAccountOnly() async throws {
        let useCase = DefaultAddDebitCardUseCase(accounts: store, cards: store)
        let card = try await useCase.execute(accountID: SampleData.IDs.payroll, lastFour: "1357", network: .visa, color: .verde)
        #expect(card.kind == .debit)
        #expect(card.accountID == SampleData.IDs.payroll)
        await #expect(throws: DomainError.invalidTransferDestination) {
            _ = try await useCase.execute(accountID: SampleData.IDs.mastercard, lastFour: "1357", network: .visa, color: .verde)
        }
    }

    @Test
    func bankAccountGetsATransferMethod() async throws {
        let account = try await DefaultAddAccountUseCase(accounts: store, cards: store)
            .execute(kind: .deposit, name: "Corriente", bank: "Banco Tres", balance: Money(50, "USD"))
        #expect(await store.fetchCards().contains { $0.accountID == account.id && $0.kind == .transfer })
    }

    @Test
    func walletNeedsANameAndNoNegativeBalance() async {
        let useCase = DefaultAddAccountUseCase(accounts: store, cards: store)
        await #expect(throws: DomainError.invalidAmount) {
            _ = try await useCase.execute(kind: .cash, name: "Sobre", bank: nil, balance: Money(-1, "NIO"))
        }
        await #expect(throws: DomainError.corruptedData("Empty account name")) {
            _ = try await useCase.execute(kind: .cash, name: " ", bank: nil, balance: Money(1, "NIO"))
        }
    }
}

@Suite("Add card context")
struct AddCardContextTests {
    @Test
    func listsBankAccountsAndSettings() async throws {
        let store = InMemoryStore(sample: .standard)
        let context = try await DefaultGetAddCardContextUseCase(settings: store, accounts: store).execute()
        #expect(context.depositAccounts.map(\.id) == [SampleData.IDs.savings, SampleData.IDs.payroll])
        #expect(context.currencies.second == "NIO")
        #expect(context.paymentReminderDaysBefore == 3)
    }
}
