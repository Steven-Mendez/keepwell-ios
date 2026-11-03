import Domain
import DomainSamples
import Foundation
import Testing
@testable import AccountsDomain

@Suite("Cash use cases")
struct CashUseCasesTests {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    @Test
    func reconcilingSavesTheShortfall() async throws {
        let store = InMemoryStore(sample: SampleData.standard)
        let cash = AccountsOverview.Cash(
            account: Account(
                id: SampleData.IDs.cash,
                name: "Billetera",
                kind: .cash,
                openingBalances: [Money(0, "NIO")],
                openingDate: date,
            ),
            balance: Money(8390, "NIO"),
            principalEquivalent: nil,
        )
        let adjustment = try await DefaultReconcileCashUseCase(transactions: store, settings: store) { [date] in date }
            .execute(cash: cash, counted: 8000)
        #expect(adjustment?.amount == 390)
        #expect(adjustment?.kind == .expense)
        #expect(await store.fetchTransactions(in: nil).contains { $0.id == adjustment?.id })
    }

    @Test
    func withdrawalIsATransferWithTheRealDebit() async throws {
        let store = InMemoryStore(sample: SampleData.standard)
        let transaction = try await DefaultWithdrawCashUseCase(transactions: store, cards: store, settings: store) { [date] in date }
            .execute(CashWithdrawal(
                sourceAccountID: SampleData.IDs.savings,
                cashAccountID: SampleData.IDs.cash,
                amount: Money(1000, "NIO"),
                debitedPrincipal: 27.5,
            ))
        #expect(transaction.kind == .transfer)
        #expect(transaction.destinationAccountID == SampleData.IDs.cash)
        #expect(transaction.cardID == SampleData.IDs.savingsTransfer)
        #expect(transaction.principalAmount == 27.5)
    }

    @Test
    func withdrawalRejectsZeroAndSameAccount() async {
        let store = InMemoryStore(sample: SampleData.standard)
        let useCase = DefaultWithdrawCashUseCase(transactions: store, cards: store, settings: store)
        await #expect(throws: DomainError.invalidAmount) {
            try await useCase.execute(CashWithdrawal(
                sourceAccountID: SampleData.IDs.savings, cashAccountID: SampleData.IDs.cash, amount: Money(0, "NIO"), debitedPrincipal: nil,
            ))
        }
        await #expect(throws: DomainError.invalidTransferDestination) {
            try await useCase.execute(CashWithdrawal(
                sourceAccountID: SampleData.IDs.cash, cashAccountID: SampleData.IDs.cash, amount: Money(5, "NIO"), debitedPrincipal: nil,
            ))
        }
    }
}
