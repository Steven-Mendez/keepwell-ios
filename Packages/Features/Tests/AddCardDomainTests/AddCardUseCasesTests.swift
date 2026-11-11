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
            bank: "Bank Three", lastFour: "2468", network: .mastercard, color: .violeta, debtMode: mode,
            principalDebt: 10, secondDebt: 250, limit: 1500, cutoffDay: 28, dueDay: 15,
        )
    }

    @Test
    func billingDaysAreOptional() async throws {
        var noDays = draft()
        noDays.cutoffDay = nil
        noDays.dueDay = nil
        let (account, _) = try await DefaultAddCreditCardUseCase(accounts: store, cards: store, settings: store).execute(noDays)
        #expect(account.creditTerms?.cutoffDay == nil)
        #expect(account.creditTerms?.dueDay == nil)
    }

    @Test
    func creditCardIsItsOwnAccountWithNegativeDebts() async throws {
        let (account, holder) = try await DefaultAddCreditCardUseCase(accounts: store, cards: store, settings: store).execute(draft())
        #expect(account.kind == .credit)
        #expect(account.openingBalances == [Money(-10, "USD"), Money(-250, "NIO")])
        #expect(try account.creditTerms == CreditTerms(debtMode: .dual, limit: Money(1500, "USD"), cutoffDay: 28, dueDay: 15))
        #expect(account.bank == "Bank Three")
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
    func aBankAccountIsCreatedWithItsOneDebitCard() async throws {
        let account = try await DefaultAddAccountUseCase(accounts: store, cards: store).execute(
            kind: .deposit, name: "Checking", bank: "Bank Three", balance: Money(50, "USD"),
            debitCard: DebitCardDraft(lastFour: "1357", network: .visa, color: .verde),
        )
        let cards = await store.fetchCards().filter { $0.accountID == account.id }
        let debit = try #require(cards.first { $0.kind == .debit })
        #expect(cards.count { $0.kind == .debit } == 1)
        #expect(debit.lastFour == "1357")
        #expect(debit.color == .verde)
        #expect(cards.contains { $0.kind == .transfer })
    }

    @Test
    func aBankAccountWithoutDigitsStillGetsItsCard() async throws {
        let account = try await DefaultAddAccountUseCase(accounts: store, cards: store)
            .execute(kind: .deposit, name: "Checking", bank: nil, balance: Money(0, "USD"))
        let debit = await store.fetchCards().first { $0.accountID == account.id && $0.kind == .debit }
        #expect(debit != nil)
        #expect(debit?.lastFour == nil)
    }

    @Test
    func badDigitsLeaveNoAccountBehind() async {
        let before = await store.fetchAccounts().count
        await #expect(throws: DomainError.invalidLastFour("12")) {
            _ = try await DefaultAddAccountUseCase(accounts: store, cards: store).execute(
                kind: .deposit, name: "Checking", bank: nil, balance: Money(0, "USD"), debitCard: DebitCardDraft(lastFour: "12"),
            )
        }
        #expect(await store.fetchAccounts().count == before)
    }

    @Test
    func cashHasNoCard() async throws {
        let account = try await DefaultAddAccountUseCase(accounts: store, cards: store)
            .execute(kind: .cash, name: "Envelope", bank: nil, balance: Money(10, "NIO"))
        #expect(await !store.fetchCards().contains { $0.accountID == account.id })
    }

    @Test
    func walletNeedsANameAndNoNegativeBalance() async {
        let useCase = DefaultAddAccountUseCase(accounts: store, cards: store)
        await #expect(throws: DomainError.invalidAmount) {
            _ = try await useCase.execute(kind: .cash, name: "Envelope", bank: nil, balance: Money(-1, "NIO"))
        }
        await #expect(throws: DomainError.missingName) {
            _ = try await useCase.execute(kind: .cash, name: " ", bank: nil, balance: Money(1, "NIO"))
        }
    }
}

@Suite("Add card context")
struct AddCardContextTests {
    @Test
    func readsTheSettings() async throws {
        let store = InMemoryStore(sample: .standard)
        let context = try await DefaultGetAddCardContextUseCase(settings: store).execute()
        #expect(context.currencies.second == "NIO")
        #expect(context.paymentReminderDaysBefore == 3)
    }
}
