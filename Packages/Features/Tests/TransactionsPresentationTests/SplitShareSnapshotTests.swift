import Domain
import DomainSamples
import FeatureTestSupport
import SwiftUI
import Testing
import TransactionsDomain
@testable import TransactionsPresentation

/// The "Your share" card of a split expense's detail, drawn on its own: the rest of the detail
/// shows the movement's time in the device's zone, which would tie the reference to the machine.
@Suite("Split share snapshots")
@MainActor
struct SplitShareSnapshotTests {
    @Test
    func yourShareCard() async throws {
        let now = SampleData.defaultReferenceDate
        let dinner = Transaction(
            date: now, description: "Dinner", kind: .expense, categoryID: "restaurants", amount: 900, currency: "NIO",
            accountID: SampleData.IDs.cash, exchangeRate: .single("NIO"),
        )
        let store = InMemoryStore(sample: .standard)
        await store.save(dinner)
        for person in ["Ana", "Luis"] {
            await store.save(PersonalDebt(
                person: person, direction: .theyOweMe, amount: Money(300, "NIO"), date: now, transactionID: dinner.id,
            ))
        }
        let viewModel = TransactionDetailViewModel(
            transactionID: dinner.id,
            getList: DefaultGetTransactionListUseCase(
                transactions: store, accounts: store, cards: store, categories: store, settings: store, personalDebts: store,
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store),
            deleteTransaction: DefaultDeleteTransactionUseCase(transactions: store),
        )
        await viewModel.load()
        let split = try #require(viewModel.splitLines)
        #expect(split.share == "Your share: C$300.00 of C$900.00")
        assertScreenSnapshot(
            of: SplitShareCard(share: split.share, people: split.people).padding(.horizontal, 16),
            height: 120,
        )
    }
}
