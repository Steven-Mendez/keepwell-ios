import DomainSamples
import Foundation
import Testing
@testable import Domain

@Suite("Card actions")
struct CardActionsTests {
    private typealias IDs = SampleData.IDs

    @Test
    func freezingAndUnfreezingAPlastic() async throws {
        let store = InMemoryStore(sample: .standard)
        let freeze = DefaultSetCardFrozenUseCase(cards: store)
        try await freeze.execute(cardID: IDs.savingsDebit, isFrozen: true)
        #expect(try await card(IDs.savingsDebit, in: store).isFrozen)
        try await freeze.execute(cardID: IDs.savingsDebit, isFrozen: false)
        #expect(try await !card(IDs.savingsDebit, in: store).isFrozen)
    }

    @Test
    func repaintingKeepsEverythingElse() async throws {
        let store = InMemoryStore(sample: .standard)
        let before = try await card(IDs.savingsDebit, in: store)
        try await DefaultSetCardColorUseCase(cards: store).execute(cardID: IDs.savingsDebit, color: .verde)
        let after = try await card(IDs.savingsDebit, in: store)
        #expect(after.color == .verde)
        #expect(after.lastFour == before.lastFour)
        #expect(after.network == before.network)
        #expect(after.accountID == before.accountID)
    }

    @Test
    func repaintingAnAdditionalKeepsItsControls() async throws {
        let store = InMemoryStore(sample: .standard)
        let before = try await card(IDs.mastercardAdditional, in: store)
        try await DefaultSetCardColorUseCase(cards: store).execute(cardID: IDs.mastercardAdditional, color: .oro)
        let after = try await card(IDs.mastercardAdditional, in: store)
        #expect(after.color == .oro)
        #expect(after.additional == before.additional)
    }

    @Test
    func aTransferChannelHasNoArtToRepaint() async {
        let store = InMemoryStore(sample: .standard)
        await #expect(throws: DomainError.notFound(IDs.savingsTransfer)) {
            try await DefaultSetCardColorUseCase(cards: store).execute(cardID: IDs.savingsTransfer, color: .verde)
        }
    }

    @Test
    func renamingTrimsTheName() async throws {
        let store = InMemoryStore(sample: .standard)
        try await DefaultRenameAccountUseCase(accounts: store).execute(accountID: IDs.savings, name: "  Travel  ")
        let account = try #require(await store.fetchAccounts().first { $0.id == IDs.savings })
        #expect(account.name == "Travel")
        #expect(account.bank == "Bank One")
    }

    @Test
    func anEmptyNameIsRefused() async {
        let store = InMemoryStore(sample: .standard)
        await #expect(throws: DomainError.missingName) {
            try await DefaultRenameAccountUseCase(accounts: store).execute(accountID: IDs.savings, name: "   ")
        }
    }

    private func card(_ id: UUID, in store: InMemoryStore) async throws -> Card {
        try #require(await store.fetchCards().first { $0.id == id })
    }
}
