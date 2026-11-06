import CreateTransactionDomain
import Domain
import DomainSamples
import Foundation
import Testing
@testable import CreateTransactionPresentation

/// Rules the offer saves fail on demand, to check the edit survives a failed rule.
private struct FailingRules: ManageCategorizationRulesUseCase {
    func rules() async throws(DomainError) -> [CategorizationRule] {
        []
    }

    func save(_: CategorizationRuleDraft) async throws(DomainError) -> CategorizationRule {
        throw .missingName
    }

    func delete(id _: UUID) async throws(DomainError) {}
    func reorder(ids _: [UUID]) async throws(DomainError) {}
    func pastMatchCount(of _: CategorizationRule) async throws(DomainError) -> Int {
        0
    }

    func applyToPast(_: CategorizationRule) async throws(DomainError) -> Int {
        0
    }

    func tagUsage() async throws(DomainError) -> [String] {
        []
    }
}

@Suite("Edit transaction view model")
@MainActor
struct EditTransactionViewModelTests {
    private typealias IDs = SampleData.IDs
    private let now = SampleData.defaultReferenceDate
    private let movementID = UUID(uuidString: "7E1A2B3C-0000-4000-8000-0000000000E2") ?? UUID()

    private func storeWithMovement(kind: TransactionKind = .expense) async -> InMemoryStore {
        let store = InMemoryStore(sample: .standard)
        let rate = SampleData.standard.settings.currencies.exchangeRate
        await store.save(Transaction(
            id: movementID,
            date: now,
            status: .planned,
            description: "Uber",
            kind: kind,
            categoryID: kind == .expense ? "restaurants" : nil,
            amount: Decimal(string: "12.5") ?? 0,
            currency: "USD",
            accountID: IDs.savings,
            cardID: IDs.savingsDebit,
            destinationAccountID: kind == .transfer ? IDs.cash : nil,
            exchangeRate: rate,
            note: "Airport",
            tags: ["viaje"],
        ))
        return store
    }

    private func make(
        _ mode: CreateTransactionViewModel.Mode,
        store: InMemoryStore,
        rules: (any ManageCategorizationRulesUseCase)? = nil,
    ) async -> CreateTransactionViewModel {
        let stored = DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: store, rules: store, now: { now },
        )
        let viewModel = CreateTransactionViewModel(
            stored: mode,
            getStored: stored,
            update: DefaultUpdateTransactionUseCase(stored: stored, transactions: store, settings: store),
            manageRules: rules ?? DefaultManageCategorizationRulesUseCase(rules: store, categories: store, transactions: store),
            now: { now },
        )
        await viewModel.load()
        return viewModel
    }

    @Test
    func anEditOpensOnTheReviewWithTheSavedFields() async {
        let viewModel = await make(.edit(movementID), store: storeWithMovement())
        #expect(viewModel.isEditing)
        #expect(viewModel.rootStep == .review)
        #expect(viewModel.type == .expense)
        #expect(viewModel.amountText == "12.5")
        #expect(viewModel.currency == "USD")
        #expect(viewModel.categoryID == "restaurants")
        #expect(viewModel.source == .card(IDs.savingsDebit))
        #expect(viewModel.description == "Uber")
        #expect(viewModel.note == "Airport")
        #expect(viewModel.tags == ["viaje"])
        #expect(viewModel.isDraft)
        #expect(viewModel.date == now)
        #expect(viewModel.ruleHint == nil)
    }

    @Test
    func everyStepReturnsToTheReview() async {
        let viewModel = await make(.edit(movementID), store: storeWithMovement())
        viewModel.editAmount()
        #expect(viewModel.path == [.amount])
        viewModel.continueFromAmount()
        #expect(viewModel.path.isEmpty)
        viewModel.editCategory()
        viewModel.selectCategory("transport")
        #expect(viewModel.path.isEmpty)
        viewModel.editSource()
        #expect(viewModel.path == [.method])
        viewModel.selectSource(.account(IDs.cash))
        #expect(viewModel.path.isEmpty)
    }

    @Test
    func aTransferEditOpensOnItsShapeAndReturnsFromTheAccounts() async {
        let viewModel = await make(.edit(movementID), store: storeWithMovement(kind: .transfer))
        #expect(viewModel.type == .withdrawal)
        #expect(viewModel.destinationAccountID == IDs.cash)
        viewModel.editSource()
        #expect(viewModel.path == [.accounts])
        viewModel.continueFromAccounts()
        #expect(viewModel.path.isEmpty)
    }

    @Test
    func savingWithoutACategoryChangeClosesWithoutOfferingARule() async {
        let store = await storeWithMovement()
        let viewModel = await make(.edit(movementID), store: store)
        viewModel.isDraft = false
        viewModel.description = "Uber to the airport"
        await viewModel.saveChanges()
        #expect(viewModel.ruleOffer == nil)
        #expect(viewModel.isFinished)
        #expect(viewModel.completionNotice == "Saved")
        let saved = await store.fetchTransactions(in: nil).first { $0.id == movementID }
        #expect(saved?.description == "Uber to the airport")
        #expect(saved?.status == .confirmed)
    }

    @Test
    func changingTheCategoryOffersARuleForTheDescription() async throws {
        let store = await storeWithMovement()
        let viewModel = await make(.edit(movementID), store: store)
        viewModel.selectCategory("transport")
        await viewModel.saveChanges()
        let offer = try #require(viewModel.ruleOffer)
        #expect(offer.title == "Always use Transport for “Uber”?")
        #expect(offer.match == "Uber")
        #expect(offer.categoryID == "transport")
        #expect(offer.kind == .expense)
        #expect(!viewModel.isFinished)

        await viewModel.acceptRuleOffer()
        #expect(viewModel.isFinished)
        #expect(viewModel.completionNotice == "Rule saved")
        let rules = await store.fetchCategorizationRules()
        #expect(rules.contains { $0.match == "Uber" && $0.categoryID == "transport" && $0.kind == .expense })
    }

    @Test
    func decliningTheOfferKeepsTheEditOnly() async {
        let store = await storeWithMovement()
        let rulesBefore = await store.fetchCategorizationRules()
        let viewModel = await make(.edit(movementID), store: store)
        viewModel.selectCategory("transport")
        await viewModel.saveChanges()
        viewModel.declineRuleOffer()
        #expect(viewModel.ruleOffer == nil)
        #expect(viewModel.isFinished)
        #expect(viewModel.completionNotice == "Saved")
        #expect(await store.fetchCategorizationRules() == rulesBefore)
        #expect(await store.fetchTransactions(in: nil).first { $0.id == movementID }?.categoryID == "transport")
    }

    @Test
    func aRuleThatFailsLeavesTheFlowOpenWithTheError() async {
        let viewModel = await make(.edit(movementID), store: storeWithMovement(), rules: FailingRules())
        viewModel.selectCategory("transport")
        await viewModel.saveChanges()
        await viewModel.acceptRuleOffer()
        #expect(!viewModel.isFinished)
        #expect(viewModel.ruleOffer == nil)
        #expect(viewModel.errorMessage == "We couldn't save the rule. Try again.")
    }

    @Test
    func aStoredReceiptShowsTheMovementWithoutLoggingAnother() async throws {
        let viewModel = await make(.receipt(movementID), store: storeWithMovement())
        #expect(viewModel.isShowingStoredReceipt)
        #expect(!viewModel.isEditing)
        #expect(viewModel.rootStep == .saved)
        let saved = try #require(viewModel.saved)
        #expect(saved.transaction.id == movementID)
        #expect(viewModel.reference(saved) == "KW-7E1A2B3C")
        #expect(viewModel.category?.id == "restaurants")
    }

    @Test
    func aMissingMovementSaysSo() async {
        let viewModel = await make(.edit(UUID()), store: InMemoryStore(sample: .standard))
        #expect(viewModel.errorMessage == "We couldn't load this movement.")
        #expect(viewModel.original == nil)
    }
}
