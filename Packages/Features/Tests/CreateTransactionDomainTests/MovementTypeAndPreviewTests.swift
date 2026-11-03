import Domain
import DomainSamples
import Foundation
import Testing
@testable import CreateTransactionDomain

@Suite("Movement types and previews")
struct MovementTypeAndPreviewTests {
    private let store = InMemoryStore(sample: .standard)
    private let now = SampleData.defaultReferenceDate

    private func context() async throws -> TransactionContext {
        try await DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: store, now: { [now] in now },
        ).execute()
    }

    private func account(_ kind: AccountKind) -> Account {
        Account(name: "\(kind)", kind: kind, openingBalances: [Money(0, "USD")], openingDate: now)
    }

    @Test
    func typesFollowTheAccountsThePersonHas() {
        let bank = account(.deposit)
        let cash = account(.cash)
        let card = account(.credit)
        #expect(MovementType.available(with: []).isEmpty)
        #expect(MovementType.available(with: [bank]) == [.expense, .income])
        #expect(MovementType.available(with: [bank, cash]) == [.expense, .income, .transfer, .withdrawal])
        #expect(MovementType.available(with: [cash, card]) == [.expense, .income, .cardPayment])
        #expect(MovementType.available(with: [bank, card]) == [.expense, .income, .cardPayment])
    }

    @Test
    func eachTransferShapeLimitsBothEnds() {
        let bank = account(.deposit)
        let cash = account(.cash)
        let card = account(.credit)
        #expect(MovementType.withdrawal.allowsSource(bank))
        #expect(!MovementType.withdrawal.allowsSource(cash))
        #expect(MovementType.withdrawal.allowsDestination(cash, from: bank.id))
        #expect(!MovementType.withdrawal.allowsDestination(card, from: bank.id))
        #expect(MovementType.cardPayment.allowsDestination(card, from: cash.id))
        #expect(!MovementType.transfer.allowsDestination(card, from: bank.id))
        #expect(!MovementType.transfer.allowsDestination(bank, from: bank.id))
        #expect(MovementType(.transfer) == .transfer)
        #expect(MovementType.cardPayment.kind == .transfer)
    }

    @Test
    func previewConvertsWhatArrivesWithTheStoredRate() async throws {
        let context = try await context()
        let draft = TransactionDraft(
            kind: .transfer, amount: 100, currency: "USD",
            source: .card(SampleData.IDs.savingsTransfer), destinationAccountID: SampleData.IDs.cash, date: now,
        )
        let preview = try #require(context.preview(of: draft))
        #expect(preview.leaving == Money(100, "USD"))
        #expect(preview.arriving == Money(Decimal(string: "3662.43") ?? 0, "NIO"))
        #expect(preview.convertsCurrency(from: "USD"))
        let savings = try #require(context.balances[SampleData.IDs.savings]?.first)
        #expect(preview.sourceAfter == [Money(savings.amount - 100, "USD")])
    }

    @Test
    func previewAgreesWithTheBalanceAfterSaving() async throws {
        let context = try await context()
        let draft = TransactionDraft(
            kind: .expense, amount: 879, currency: "NIO", categoryID: "restaurants",
            source: .card(SampleData.IDs.savingsDebit), date: now, actualDebitedPrincipal: Decimal(string: "24.28"),
        )
        let preview = try #require(context.preview(of: draft))
        let saved = try await DefaultSaveTransactionUseCase(context: DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: store, now: { [now] in now },
        ), transactions: store).execute(draft)
        #expect(preview.sourceAfter == saved.newBalances)
        #expect(preview.leaving == Money(Decimal(string: "24.28") ?? 0, "USD"))
    }
}
