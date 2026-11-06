import Domain
import DomainSamples
import Foundation
import Testing
@testable import CreateTransactionDomain

@Suite("Create transaction")
struct CreateTransactionUseCasesTests {
    private let store = InMemoryStore(sample: .standard)
    private let now = SampleData.defaultReferenceDate

    private func contextUseCase() -> DefaultGetTransactionContextUseCase {
        DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: store, now: { [now] in now },
        )
    }

    private func save(_ draft: TransactionDraft) async throws -> SavedTransaction {
        try await DefaultSaveTransactionUseCase(context: contextUseCase(), transactions: store).execute(draft)
    }

    private func expense(_ amount: Decimal = 879, currency: String = "NIO", source: PaymentSource) -> TransactionDraft {
        TransactionDraft(kind: .expense, amount: amount, currency: currency, categoryID: "restaurants", source: source, date: now)
    }

    @Test
    func contextKnowsBalancesLastUsedAndCaps() async throws {
        let context = try await contextUseCase().execute()
        #expect(context.balances[SampleData.IDs.cash]?.first?.currency == "NIO")
        #expect(context.lastUsedSource != nil)
        #expect(context.additionalUsage[SampleData.IDs.mastercardAdditional]?.cap == Money(4000, "NIO"))
        #expect(context.accountID(for: .card(SampleData.IDs.savingsDebit)) == SampleData.IDs.savings)
    }

    @Test
    func savingDerivesTheAccountAndStoresTheCurrentRate() async throws {
        var draft = expense(source: .card(SampleData.IDs.savingsDebit))
        draft.actualDebitedPrincipal = 24.28
        draft.description = "  Dinner  "
        let saved = try await save(draft)
        #expect(saved.transaction.accountID == SampleData.IDs.savings)
        #expect(saved.transaction.exchangeRate == SampleData.standard.settings.currencies.exchangeRate)
        #expect(saved.transaction.description == "Dinner")
        #expect(saved.transaction.bankRate.map { $0.rounded(scale: 2) } == Decimal(string: "36.20"))
        #expect(saved.account.id == SampleData.IDs.savings)
        #expect(saved.categoryMonthTotal?.currency == "USD")
    }

    @Test
    func newBalanceReflectsTheMovementUnlessPlanned() async throws {
        let before = try await contextUseCase().execute().balances[SampleData.IDs.cash]?.first?.amount ?? 0
        let saved = try await save(expense(100, source: .account(SampleData.IDs.cash)))
        #expect(saved.newBalances.first?.amount == before - 100)
        var planned = expense(50, source: .account(SampleData.IDs.cash))
        planned.isPlanned = true
        let plannedSaved = try await save(planned)
        #expect(plannedSaved.transaction.status == .planned)
        #expect(plannedSaved.newBalances.first?.amount == before - 100)
    }

    @Test
    func emptyDescriptionFallsBackToTheCategory() async throws {
        let saved = try await save(expense(source: .account(SampleData.IDs.cash)))
        #expect(saved.transaction.description == "Restaurants")
    }

    @Test
    func rejectsZeroAmountsForeignCurrenciesAndMismatchedCategories() async {
        await #expect(throws: DomainError.invalidAmount) { _ = try await save(expense(0, source: .account(SampleData.IDs.cash))) }
        await #expect(throws: DomainError.invalidCurrency("EUR")) {
            _ = try await save(expense(currency: "EUR", source: .account(SampleData.IDs.cash)))
        }
        var income = expense(source: .account(SampleData.IDs.cash))
        income.kind = .income
        await #expect(throws: DomainError.categoryKindMismatch(expected: .income, actual: .expense)) { _ = try await save(income) }
    }

    @Test
    func additionalCardOnlyAcceptsItsCategories() async {
        await #expect(throws: DomainError.paymentMethodUnavailable(SampleData.IDs.mastercardAdditional)) {
            _ = try await save(expense(source: .card(SampleData.IDs.mastercardAdditional)))
        }
    }

    @Test
    func transfersNeedADifferentDestination() async throws {
        var transfer = TransactionDraft(
            kind: .transfer, amount: 500, currency: "NIO", source: .card(SampleData.IDs.savingsTransfer), date: now,
        )
        await #expect(throws: DomainError.invalidTransferDestination) { _ = try await save(transfer) }
        transfer.destinationAccountID = SampleData.IDs.savings
        await #expect(throws: DomainError.invalidTransferDestination) { _ = try await save(transfer) }
        transfer.destinationAccountID = SampleData.IDs.cash
        transfer.categoryID = "restaurants"
        let saved = try await save(transfer)
        #expect(saved.transaction.categoryID == nil)
        #expect(saved.transaction.description == "Transfer")
        #expect(saved.categoryMonthTotal == nil)
    }

    @Test
    func principalCurrencyIgnoresTheRealDebitField() async throws {
        var draft = expense(20, currency: "USD", source: .card(SampleData.IDs.savingsDebit))
        draft.actualDebitedPrincipal = 21
        let saved = try await save(draft)
        #expect(saved.transaction.actualDebitedPrincipal == nil)
    }
}
