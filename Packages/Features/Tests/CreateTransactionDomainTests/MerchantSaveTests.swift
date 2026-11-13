import Domain
import DomainSamples
import Foundation
import Testing
@testable import CreateTransactionDomain

/// Saving a movement with a business and a platform (keepwell-web's `categorizedTransaction` and
/// `merchantLinks`). The sample ledger has the rule "Uber → Transport".
@Suite("Merchants when saving a movement")
struct MerchantSaveTests {
    private typealias IDs = SampleData.IDs
    private let now = SampleData.defaultReferenceDate
    private let subway = Merchant(name: "Subway", domain: "subway.com", brandID: "subway", defaultCategoryID: "restaurants")
    private let uberEats = Merchant(name: "Uber Eats", domain: "ubereats.com", isPlatform: true)
    private let uber = Merchant(name: "Uber", domain: "uber.com")

    private func store(rules: [CategorizationRule]? = nil) -> InMemoryStore {
        let sample = SampleData.standard
        return InMemoryStore(
            accounts: sample.accounts, cards: sample.cards, transactions: sample.transactions, categories: sample.categories,
            settings: sample.settings, recurringRules: sample.recurringRules,
            categorizationRules: rules ?? sample.categorizationRules, merchants: [subway, uberEats, uber],
        )
    }

    private func context(_ store: InMemoryStore) -> DefaultGetTransactionContextUseCase {
        DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: store, rules: store, merchants: store,
            now: { [now] in now },
        )
    }

    private func save(_ draft: TransactionDraft, in store: InMemoryStore) async throws -> Transaction {
        try await DefaultSaveTransactionUseCase(
            context: context(store), transactions: store, recurringRules: store, merchants: store,
        ).execute(draft).transaction
    }

    private func update(_ draft: TransactionDraft, in store: InMemoryStore) async throws -> Transaction {
        try await DefaultUpdateTransactionUseCase(stored: context(store), transactions: store, settings: store, merchants: store)
            .execute(draft).transaction
    }

    private func expense(
        _ description: String,
        category: String? = nil,
        merchant: MerchantLink = .keep,
        via: MerchantLink = .keep,
        id: UUID = UUID(),
    ) -> TransactionDraft {
        TransactionDraft(
            id: id, kind: .expense, amount: 100, currency: "NIO", categoryID: category, source: .account(IDs.cash),
            description: description, date: now, merchant: merchant, via: via,
        )
    }

    @Test
    func aNewMovementWithoutACategoryTakesItsMerchantsDefault() async throws {
        let store = store()
        let saved = try await save(expense("Lunch", merchant: .merchant(subway.id), via: .merchant(uberEats.id)), in: store)
        #expect(saved.categoryID == "restaurants")
        #expect(saved.merchantID == subway.id)
        #expect(saved.viaMerchantID == uberEats.id)
        // A category the person picked stays.
        #expect(try await save(expense("Lunch", category: "groceries", merchant: .merchant(subway.id)), in: store)
            .categoryID == "groceries")
        // An income doesn't take an expense default.
        var income = expense("Refund", merchant: .merchant(subway.id))
        income.kind = .income
        #expect(try await save(income, in: store).categoryID == TransactionCategory.otherIncomeID)
    }

    /// A matching rule decides first; the merchant's default only applies when none matches.
    @Test
    func aMatchingRuleWinsOverTheMerchantsDefault() async throws {
        let store = store()
        let saved = try await save(expense("Uber trip", merchant: .merchant(subway.id)), in: store)
        #expect(saved.categoryID == "transport")
        #expect(saved.merchantID == subway.id)
    }

    @Test
    func aRuleSetsItsMerchantWhenTheMovementNamesNone() async throws {
        let rule = CategorizationRule(match: "Uber", categoryID: "transport", kind: .expense, tags: ["ride"], merchantID: uber.id)
        let store = store(rules: [rule])
        let saved = try await save(expense("Uber home"), in: store)
        #expect(saved.categoryID == "transport")
        #expect(saved.merchantID == uber.id)
        #expect(saved.tags == ["ride"])
        // One the person picked stays.
        #expect(try await save(expense("Uber home", merchant: .merchant(subway.id)), in: store).merchantID == subway.id)
        // Cleared on purpose: the rule still categorizes and tags, never links.
        let cleared = try await save(expense("Uber home", merchant: .unlinked), in: store)
        #expect(cleared.categoryID == "transport")
        #expect(cleared.tags == ["ride"])
        #expect(cleared.merchantID == nil)
    }

    @Test
    func aRuleNamingAMerchantThatIsGoneLinksNothing() async throws {
        let rule = CategorizationRule(match: "Uber", categoryID: "transport", kind: .expense, merchantID: UUID())
        let saved = try await save(expense("Uber home"), in: store(rules: [rule]))
        #expect(saved.categoryID == "transport")
        #expect(saved.merchantID == nil)
    }

    @Test
    func unknownLinksAndAPlatformThatIsTheBusinessAreDropped() async throws {
        let store = store()
        let unknown = try await save(expense("Lunch", category: "restaurants", merchant: .merchant(UUID())), in: store)
        #expect(unknown.merchantID == nil)
        let same = try await save(
            expense("Lunch", category: "restaurants", merchant: .merchant(subway.id), via: .merchant(subway.id)),
            in: store,
        )
        #expect(same.merchantID == subway.id)
        #expect(same.viaMerchantID == nil)
    }

    @Test
    func anEditKeepsLeftOutLinksAndClearsUnlinkedOnes() async throws {
        let store = store()
        let id = UUID()
        _ = try await save(
            expense("Lunch", category: "restaurants", merchant: .merchant(subway.id), via: .merchant(uberEats.id), id: id),
            in: store,
        )
        // A caller that doesn't know merchants (`keep`) never unlinks them.
        var draft = expense("Lunch at the mall", category: "restaurants", id: id)
        var edited = try await update(draft, in: store)
        #expect(edited.merchantID == subway.id)
        #expect(edited.viaMerchantID == uberEats.id)
        // An edit never takes a default category or a rule.
        draft.via = .unlinked
        edited = try await update(draft, in: store)
        #expect(edited.merchantID == subway.id)
        #expect(edited.viaMerchantID == nil)
        draft.merchant = .unlinked
        #expect(try await update(draft, in: store).merchantID == nil)
    }

    @Test
    func anEditKeepsAStoredLinkToAMerchantNotPulledYet() async throws {
        let store = store()
        let ghost = UUID()
        let movement = Transaction(
            date: now, description: "Lunch", kind: .expense, categoryID: "restaurants", amount: 10, currency: "NIO",
            accountID: IDs.cash, exchangeRate: SampleData.standard.settings.currencies.exchangeRate, merchantID: ghost,
        )
        await store.save(movement)
        var draft = TransactionDraft(editing: movement)
        draft.note = "edited"
        #expect(try await update(draft, in: store).merchantID == ghost)
    }

    @Test
    func aTransferNamesNoMerchant() async throws {
        let store = store()
        let id = UUID()
        _ = try await save(
            expense("Lunch", category: "restaurants", merchant: .merchant(subway.id), via: .merchant(uberEats.id), id: id),
            in: store,
        )
        var transfer = expense("Move", merchant: .keep, via: .keep, id: id)
        transfer.kind = .transfer
        transfer.categoryID = nil
        transfer.destinationAccountID = IDs.savings
        let edited = try await update(transfer, in: store)
        #expect(edited.merchantID == nil)
        #expect(edited.viaMerchantID == nil)
        // A new transfer creates no merchant either.
        var new = expense("Move", merchant: .new(MerchantDraft(name: "Banco")))
        new.kind = .transfer
        new.destinationAccountID = IDs.savings
        #expect(try await save(new, in: store).merchantID == nil)
        #expect(try await store.fetchMerchants().count == 3)
    }

    @Test
    func aMerchantPickedNewIsCreatedWithTheMovement() async throws {
        let store = store()
        let saved = try await save(
            expense(
                "Pizza",
                merchant: .new(MerchantDraft(name: "Papa John's", domain: "papajohns.com")),
                via: .new(MerchantDraft(name: "Uber Eats", domain: "ubereats.com")),
            ),
            in: store,
        )
        let merchants = try await store.fetchMerchants()
        let created = try #require(merchants.first { $0.name == "Papa John's" })
        #expect(saved.merchantID == created.id)
        // "Uber Eats" was there already: it is reused, not made twice.
        #expect(saved.viaMerchantID == uberEats.id)
        #expect(merchants.count == 4)
    }

    @Test
    func aSaveThatFailsLeavesNoMerchantBehind() async throws {
        let store = store()
        var draft = expense("Pizza", merchant: .new(MerchantDraft(name: "Papa John's")))
        draft.amount = 0
        await #expect(throws: DomainError.invalidAmount) { try await save(draft, in: store) }
        #expect(try await store.fetchMerchants().count == 3)
    }

    @Test
    func repeatCarriesTheLinksToTheRecurringRule() async throws {
        let store = store()
        var draft = expense("Lunch", category: "restaurants", merchant: .merchant(subway.id), via: .merchant(uberEats.id))
        draft.repeatFrequency = .monthly
        _ = try await save(draft, in: store)
        let rule = try #require(try await store.fetchRecurringRules().first { $0.id == draft.recurringRuleID })
        #expect(rule.merchantID == subway.id)
        #expect(rule.viaMerchantID == uberEats.id)
    }
}
