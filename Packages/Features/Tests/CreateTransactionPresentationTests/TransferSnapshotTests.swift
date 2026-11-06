import CreateTransactionDomain
import DomainSamples
import FeatureTestSupport
import SwiftUI
import Testing
@testable import CreateTransactionPresentation

@Suite("Transfer snapshots")
@MainActor
struct TransferSnapshotTests {
    private func transfer() async -> CreateTransactionViewModel {
        let viewModel = await CreateTransactionFactory.loaded(.transfer)
        viewModel.selectSourceAccount(SampleData.IDs.savings)
        viewModel.selectDestination(SampleData.IDs.cash)
        return viewModel
    }

    @Test
    func menu() async {
        let store = InMemoryStore(sample: .standard)
        let menu = NewMovementMenuViewModel(getContext: DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: store,
        ))
        await menu.load()
        assertScreenSnapshot(of: NewMovementSheet(viewModel: menu, onSelect: { _ in }, onClose: {}), height: 460)
    }

    @Test
    func accounts() async {
        await assertScreenSnapshot(of: AccountsStepView(viewModel: transfer()) {})
    }

    @Test
    func amount() async {
        let viewModel = await transfer()
        viewModel.continueFromAccounts()
        for key in [1, 0, 0] {
            viewModel.press(.digit(key))
        }
        assertScreenSnapshot(of: AmountView(viewModel: viewModel) {})
    }

    @Test
    func review() async {
        let viewModel = await transfer()
        for key in [1, 0, 0] {
            viewModel.press(.digit(key))
        }
        viewModel.note = "Weekend market"
        assertScreenSnapshot(of: ReviewView(viewModel: viewModel) {})
    }
}
