import Domain
import DomainSamples
import FeatureTestSupport
import SwiftUI
import Testing
import TransactionsDomain
@testable import TransactionsPresentation

@Suite("Transactions snapshots")
@MainActor
struct TransactionsSnapshotTests {
    private func loaded() async -> TransactionsViewModel {
        let store = InMemoryStore(sample: .standard)
        let viewModel = TransactionsViewModel(
            getList: DefaultGetTransactionListUseCase(
                transactions: store, accounts: store, cards: store, categories: store, settings: store,
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store),
            deleteTransaction: DefaultDeleteTransactionUseCase(transactions: store),
            now: { SampleData.defaultReferenceDate },
        )
        await viewModel.load()
        return viewModel
    }

    @Test
    func transactions() async {
        await assertScreenSnapshot(of: TransactionsView(viewModel: loaded(), onNewMovement: {}), height: 1200)
    }

    @Test
    func transactionsLight() async {
        await assertScreenSnapshot(
            of: TransactionsView(viewModel: loaded(), onNewMovement: {}),
            height: 1200,
            named: "light",
            colorScheme: .light,
        )
    }
}
