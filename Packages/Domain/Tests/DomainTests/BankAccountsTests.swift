import DomainSamples
import Foundation
import Testing
@testable import Domain

@Suite("One bank account, one card")
struct BankAccountsTests {
    private typealias IDs = SampleData.IDs

    @discardableResult
    private func normalize(_ store: InMemoryStore) async throws -> Bool {
        try await DefaultNormalizeBankCardsUseCase(accounts: store, cards: store, transactions: store).execute()
    }

    private func debits(of accountID: UUID, in store: InMemoryStore) async -> [Card] {
        await store.fetchCards().filter { $0.accountID == accountID && $0.kind == .debit }
    }

    @Test
    func dataThatFollowsTheRuleIsLeftAlone() async throws {
        let store = InMemoryStore(sample: .standard)
        let before = await store.fetchCards()
        #expect(try await !normalize(store))
        #expect(await store.fetchCards() == before)
    }

    @Test
    func extraDebitCardsMergeIntoTheMostUsedOneAndKeepTheirMovements() async throws {
        let store = InMemoryStore(sample: .standard)
        let spare = try Card(accountID: IDs.savings, kind: .debit, network: .mastercard, lastFour: "4444", color: .verde)
        await store.save(spare)
        let spent = Fixtures.transaction(amount: "12", account: IDs.savings, card: spare.id)
        await store.save(spent)
        let countBefore = await store.fetchTransactions(in: nil).count

        #expect(try await normalize(store))

        #expect(await debits(of: IDs.savings, in: store).map(\.id) == [IDs.savingsDebit])
        let movements = await store.fetchTransactions(in: nil)
        #expect(movements.count == countBefore)
        #expect(movements.first { $0.id == spent.id }?.cardID == IDs.savingsDebit)
        #expect(!movements.contains { $0.cardID == spare.id })
    }

    @Test
    func theMostUsedCardWinsEvenWhenAddedLater() async throws {
        let account = Account(name: "Main", kind: .deposit, openingBalances: [Money(0, "USD")], openingDate: .distantPast)
        let old = try Card(accountID: account.id, kind: .debit, lastFour: "1111")
        let used = try Card(accountID: account.id, kind: .debit, lastFour: "2222")
        let transfer = try Card(accountID: account.id, kind: .transfer)
        let store = InMemoryStore(
            accounts: [account],
            cards: [old, used, transfer],
            transactions: [
                Fixtures.transaction(amount: "1", account: account.id, card: old.id),
                Fixtures.transaction(amount: "2", account: account.id, card: used.id),
                Fixtures.transaction(amount: "3", account: account.id, card: used.id),
            ],
        )
        try await normalize(store)
        #expect(await debits(of: account.id, in: store).map(\.id) == [used.id])
        #expect(await store.fetchTransactions(in: nil).allSatisfy { $0.cardID == used.id })
    }

    @Test
    func onATieTheOldestCardWins() {
        let accountID = UUID()
        let first = try? Card(accountID: accountID, kind: .debit)
        let second = try? Card(accountID: accountID, kind: .debit)
        let methods = [first, second].compactMap(\.self)
        #expect(DefaultNormalizeBankCardsUseCase.keeper(of: methods, movements: [])?.id == first?.id)
    }

    @Test
    func anAccountWithoutCardsGetsADebitCardAndATransferChannel() async throws {
        let account = Account(name: "Bare", kind: .deposit, openingBalances: [Money(0, "USD")], openingDate: .distantPast)
        let store = InMemoryStore(accounts: [account])
        try await normalize(store)
        let cards = await store.fetchCards().filter { $0.accountID == account.id }
        #expect(cards.map(\.kind).sorted { $0.rawValue < $1.rawValue } == [.debit, .transfer])
        #expect(try await !normalize(store))
    }

    @Test
    func aDebitCardWithoutDigitsStillExists() throws {
        let card = try Card.debit(for: UUID(), lastFour: " ")
        #expect(card.kind == .debit)
        #expect(card.lastFour == nil)
    }

    @Test
    func deletingAnAccountTakesItsCardsAndMovements() async throws {
        let store = InMemoryStore(sample: .standard)
        try await DefaultDeleteAccountUseCase(accounts: store, cards: store, transactions: store).execute(accountID: IDs.savings)
        #expect(await !store.fetchAccounts().contains { $0.id == IDs.savings })
        #expect(await !store.fetchCards().contains { $0.accountID == IDs.savings })
        #expect(await !store.fetchTransactions(in: nil).contains { TransactionScope.account(IDs.savings).includes($0) })
        #expect(await store.fetchAccounts().contains { $0.id == IDs.payroll })
    }

    @Test
    func deletingAMissingAccountFails() async {
        let store = InMemoryStore(sample: .standard)
        let id = UUID()
        await #expect(throws: DomainError.notFound(id)) {
            try await DefaultDeleteAccountUseCase(accounts: store, cards: store, transactions: store).execute(accountID: id)
        }
    }
}
