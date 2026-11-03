import Domain
import DomainSamples
import Foundation
import Testing
@testable import CreateTransactionDomain

@Suite("Frozen cards")
struct FrozenCardTests {
    private let store = InMemoryStore(sample: .standard)

    @Test
    func aFrozenHolderCardCantPay() async throws {
        let holder = try #require(SampleData.standard.cards.first { $0.id == SampleData.IDs.mastercardHolder })
        await store.save(holder.with(isFrozen: true))
        let context = DefaultGetTransactionContextUseCase(
            settings: store,
            categories: store,
            accounts: store,
            cards: store,
            transactions: store,
        )
        let draft = TransactionDraft(
            kind: .expense, amount: 100, currency: "NIO", categoryID: "restaurants", source: .card(holder.id),
        )
        await #expect(throws: DomainError.paymentMethodUnavailable(holder.id)) {
            _ = try await DefaultSaveTransactionUseCase(context: context, transactions: store).execute(draft)
        }
    }

    @Test
    func freezingKeepsEverythingElseAboutTheCard() throws {
        let holder = try #require(SampleData.standard.cards.first { $0.id == SampleData.IDs.mastercardHolder })
        let frozen = holder.with(isFrozen: true)
        #expect(frozen.isFrozen)
        #expect(frozen.lastFour == holder.lastFour)
        #expect(frozen.with(isFrozen: false) == holder)
    }
}
