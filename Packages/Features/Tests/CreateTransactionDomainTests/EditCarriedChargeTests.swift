import Domain
import DomainSamples
import Foundation
import Testing
@testable import CreateTransactionDomain

/// "Movies" in the sample: C$739.32 from savings (kept in dollars), charged US$20.42 by the bank.
@Suite("Editing a movement charged in the principal currency")
struct EditCarriedChargeTests {
    private typealias IDs = SampleData.IDs
    private let store = InMemoryStore(sample: .standard)
    private let now = SampleData.defaultReferenceDate

    private func contextUseCase() -> DefaultGetTransactionContextUseCase {
        DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: store, rules: store,
            now: { [now] in now },
        )
    }

    private func update(_ draft: TransactionDraft) async throws -> SavedTransaction {
        try await DefaultUpdateTransactionUseCase(stored: contextUseCase(), transactions: store, settings: store).execute(draft)
    }

    private func movies() async throws -> Transaction {
        try #require(await store.fetchTransactions(in: nil).first { $0.description == "Movies" })
    }

    private func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    @Test
    func keepsTheChargeWhenNothingItWasChargedForChanges() async throws {
        let original = try await movies()
        #expect(original.actualDebitedPrincipal == decimal("20.42"))
        var draft = TransactionDraft(editing: original)
        #expect(draft.debitedFor == .init(amount: decimal("739.32"), currency: "NIO", accountID: IDs.savings))
        draft.description = "Cinema"
        draft.note = "with Ana"
        // Another method of the same account: the account it was charged to stays.
        draft.source = .account(IDs.savings)
        #expect(try await update(draft).transaction.actualDebitedPrincipal == decimal("20.42"))
    }

    @Test
    func dropsTheChargeWhenTheAmountChanges() async throws {
        var draft = try await TransactionDraft(editing: movies())
        draft.amount = 800
        let saved = try await update(draft)
        #expect(saved.transaction.amount == 800)
        #expect(saved.transaction.actualDebitedPrincipal == nil)
    }

    @Test
    func dropsTheChargeWhenTheCurrencyChanges() async throws {
        let draft = try await TransactionDraft(editing: movies())
        var inDollars = draft
        inDollars.currency = "USD"
        #expect(try await update(inDollars).transaction.actualDebitedPrincipal == nil)
        // Even to a currency that isn't the principal one: the charge was for córdobas.
        var inEuros = draft
        inEuros.currency = "EUR"
        #expect(inEuros.applicableDebit(principal: "USD", accountID: IDs.savings) == nil)
        #expect(draft.applicableDebit(principal: "USD", accountID: IDs.savings) == decimal("20.42"))
    }

    @Test
    func dropsTheChargeWhenTheAccountChangesToOneInAnotherCurrency() async throws {
        let original = try await movies()
        var draft = TransactionDraft(editing: original)
        let context = try await contextUseCase().execute(id: original.id).context
        #expect(context.preview(of: draft)?.leaving == Money(decimal("20.42"), "USD"))
        draft.source = .account(IDs.cash)
        #expect(context.preview(of: draft)?.leaving == Money(decimal("739.32"), "NIO"))
        let saved = try await update(draft)
        #expect(saved.transaction.accountID == IDs.cash)
        #expect(saved.transaction.actualDebitedPrincipal == nil)
    }

    @Test
    func keepsAChargeTypedForTheNewAmount() async throws {
        var draft = try await TransactionDraft(editing: movies())
        draft.debitedFor = nil
        draft.amount = 800
        draft.actualDebitedPrincipal = decimal("22.10")
        #expect(try await update(draft).transaction.actualDebitedPrincipal == decimal("22.1"))
    }

    @Test
    func aMovementInThePrincipalCurrencyNeverCarriesOne() {
        let stored = Transaction(
            date: now, description: "Hosting", kind: .expense, categoryID: "subscriptions", amount: 20,
            currency: "USD", accountID: IDs.savings, actualDebitedPrincipal: 21,
            exchangeRate: SampleData.standard.settings.currencies.exchangeRate,
        )
        let draft = TransactionDraft(editing: stored)
        #expect(draft.actualDebitedPrincipal == nil)
        #expect(draft.debitedFor == nil)
    }
}
