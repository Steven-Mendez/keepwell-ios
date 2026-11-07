import Domain
import DomainSamples
import Foundation
import Testing
@testable import CreateTransactionDomain

@Suite("Edit transaction")
struct EditTransactionTests {
    private typealias IDs = SampleData.IDs
    private let store = InMemoryStore(sample: .standard)
    private let now = SampleData.defaultReferenceDate
    private let movementID = UUID(uuidString: "7E1A2B3C-0000-4000-8000-0000000000E1") ?? UUID()
    /// Not the settings' rate, so keeping it is visible.
    private let oldRate = (try? ExchangeRate(principal: "USD", second: "NIO", rate: 36)) ?? .single("USD")

    private func contextUseCase() -> DefaultGetTransactionContextUseCase {
        DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: store, rules: store,
            now: { [now] in now },
        )
    }

    private func update(_ draft: TransactionDraft) async throws -> SavedTransaction {
        try await DefaultUpdateTransactionUseCase(stored: contextUseCase(), transactions: store, settings: store).execute(draft)
    }

    /// A shared dinner in córdobas, from the rent's recurring rule, tagged and recorded at an older rate.
    private func storeMovement(status: TransactionStatus = .confirmed) async -> Transaction {
        let movement = Transaction(
            id: movementID,
            date: now,
            status: status,
            description: "Dinner",
            kind: .expense,
            categoryID: "restaurants",
            amount: 720,
            currency: "NIO",
            accountID: IDs.savings,
            cardID: IDs.savingsDebit,
            exchangeRate: oldRate,
            isShared: true,
            note: "With Ana",
            recurringID: IDs.rentRule,
            tags: ["viaje"],
        )
        await store.save(movement)
        return movement
    }

    @Test
    func anEditKeepsTheIdRateSharingRuleAndTags() async throws {
        let original = await storeMovement()
        var draft = TransactionDraft(editing: original)
        draft.amount = 900
        draft.categoryID = "transport"
        draft.description = "  Taxi  "
        let saved = try await update(draft)
        let stored = await store.fetchTransactions(in: nil).filter { $0.id == movementID }
        #expect(stored.count == 1)
        #expect(stored.first == saved.transaction)
        #expect(saved.transaction.id == movementID)
        #expect(saved.transaction.amount == 900)
        #expect(saved.transaction.categoryID == "transport")
        #expect(saved.transaction.description == "Taxi")
        #expect(saved.transaction.exchangeRate == oldRate)
        #expect(saved.transaction.isShared)
        #expect(saved.transaction.recurringID == IDs.rentRule)
        #expect(saved.transaction.tags == ["viaje"])
        #expect(saved.transaction.note == "With Ana")
    }

    @Test
    func theAccountFollowsTheNewPaymentMethod() async throws {
        let original = await storeMovement()
        var draft = TransactionDraft(editing: original)
        draft.source = .account(IDs.cash)
        let saved = try await update(draft)
        #expect(saved.transaction.accountID == IDs.cash)
        #expect(saved.transaction.cardID == nil)
        #expect(saved.account.id == IDs.cash)
    }

    @Test
    func anEditCanTurnADraftIntoAConfirmedMovementAndBack() async throws {
        let original = await storeMovement(status: .planned)
        var draft = TransactionDraft(editing: original)
        #expect(draft.isDraft)
        draft.isDraft = false
        #expect(try await update(draft).transaction.status == .confirmed)
        draft.isDraft = true
        #expect(try await update(draft).transaction.status == .planned)
    }

    @Test
    func anEditAppliesTheSameRulesAsLogging() async throws {
        let original = await storeMovement()
        var draft = TransactionDraft(editing: original)
        draft.amount = 0
        await #expect(throws: DomainError.invalidAmount) { _ = try await update(draft) }
        draft = TransactionDraft(editing: original)
        draft.currency = "EUR"
        await #expect(throws: DomainError.invalidCurrency("EUR")) { _ = try await update(draft) }
        draft = TransactionDraft(editing: original)
        draft.categoryID = "salary"
        await #expect(throws: DomainError.categoryKindMismatch(expected: .expense, actual: .income)) { _ = try await update(draft) }
        // Nothing was written by the failed attempts.
        #expect(await store.fetchTransactions(in: nil).first { $0.id == movementID } == original)
    }

    @Test
    func theRecordedRateDecidesTheCurrenciesAfterSettingsChange() async throws {
        let original = await storeMovement()
        let euros = try CurrencySettings(principal: "EUR")
        await store.save(Settings(currencies: euros, hasCompletedOnboarding: true))
        var draft = TransactionDraft(editing: original)
        draft.currency = "USD"
        draft.amount = 20
        let saved = try await update(draft)
        #expect(saved.transaction.currency == "USD")
        #expect(saved.transaction.exchangeRate == oldRate)
        await #expect(throws: DomainError.invalidCurrency("EUR")) {
            var inEuros = draft
            inEuros.currency = "EUR"
            _ = try await update(inEuros)
        }
    }

    @Test
    func aPrincipalCurrencyEditDropsTheBankCharge() async throws {
        let original = await storeMovement()
        var draft = TransactionDraft(editing: original)
        draft.actualDebitedPrincipal = 20
        #expect(try await update(draft).transaction.actualDebitedPrincipal == 20)
        draft.currency = "USD"
        #expect(try await update(draft).transaction.actualDebitedPrincipal == nil)
    }

    @Test
    func editingNeverStartsARecurringRule() async throws {
        let original = await storeMovement()
        let rulesBefore = await store.fetchRecurringRules()
        var draft = TransactionDraft(editing: original)
        draft.repeatFrequency = .monthly
        let saved = try await update(draft)
        #expect(saved.transaction.recurringID == IDs.rentRule)
        #expect(await store.fetchRecurringRules() == rulesBefore)
    }

    @Test
    func aMissingMovementCantBeEdited() async {
        let draft = TransactionDraft(id: movementID, amount: 10, currency: "NIO", categoryID: "restaurants", source: .account(IDs.cash))
        await #expect(throws: DomainError.notFound(movementID)) { _ = try await update(draft) }
    }

    @Test
    func theStoredContextLeavesTheMovementOutOfBalancesAndUsesItsRate() async throws {
        let before = try await contextUseCase().execute().balances[IDs.savings]
        _ = await storeMovement()
        let stored = try await contextUseCase().execute(id: movementID)
        #expect(stored.context.balances[IDs.savings] == before)
        #expect(stored.context.currencies.exchangeRate == oldRate)
        #expect(stored.context.rules.isEmpty)
        #expect(stored.receipt.transaction.id == movementID)
        #expect(stored.receipt.account.id == IDs.savings)
        #expect(stored.receipt.categoryMonthTotal?.currency == "USD")
    }

    @Test
    func aSavedTransferReadsAsItsShape() async {
        let accounts = await store.fetchAccounts()
        func transfer(from source: UUID, to destination: UUID) -> Transaction {
            Transaction(
                date: now, description: "", kind: .transfer, categoryID: nil, amount: 1, currency: "USD",
                accountID: source, destinationAccountID: destination, exchangeRate: oldRate,
            )
        }
        #expect(MovementType(of: transfer(from: IDs.savings, to: IDs.mastercard), accounts: accounts) == .cardPayment)
        #expect(MovementType(of: transfer(from: IDs.savings, to: IDs.cash), accounts: accounts) == .withdrawal)
        #expect(MovementType(of: transfer(from: IDs.savings, to: IDs.payroll), accounts: accounts) == .transfer)
        let original = await storeMovement()
        #expect(MovementType(of: original, accounts: accounts) == .expense)
    }
}
