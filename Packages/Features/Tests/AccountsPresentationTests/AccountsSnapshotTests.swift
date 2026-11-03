import AccountsDomain
import FeatureTestSupport
import SwiftUI
import Testing
@testable import AccountsPresentation

@Suite("Accounts snapshots")
@MainActor
struct AccountsSnapshotTests {
    @Test
    func accountsWithSampleData() async {
        let viewModel = await AccountsFactory.loaded()
        assertScreenSnapshot(
            of: AccountsView(
                viewModel: viewModel,
                onAdd: {},
                onOpenCreditCard: { _ in },
                onOpenBankAccount: { _ in },
                onOpenAccountMovements: { _ in },
            ),
            height: 1500,
        )
    }

    @Test
    func bankAccountIsOneCardFace() async throws {
        let viewModel = await AccountsFactory.loaded()
        let deposit = try #require(viewModel.overview?.deposits.first)
        assertScreenSnapshot(of: DepositCard(deposit: deposit, formatter: .init()) {}.padding(16), height: 280)
    }

    @Test
    func debitCardDetail() async {
        let viewModel = await DebitCardFactory.loaded()
        assertScreenSnapshot(
            of: DebitCardView(viewModel: viewModel, onBack: {}, onSeeAllMovements: { _ in }),
            height: 1500,
        )
    }

    @Test
    func frozenDebitCardDetail() async {
        let viewModel = await DebitCardFactory.loaded()
        await viewModel.toggleFrozen()
        assertScreenSnapshot(
            of: DebitCardView(viewModel: viewModel, onBack: {}, onSeeAllMovements: { _ in }),
            height: 1500,
        )
    }

    @Test
    func cashSheets() async throws {
        let viewModel = await AccountsFactory.loaded()
        let cash = try #require(viewModel.overview?.cash.first)
        assertScreenSnapshot(
            of: ReconcileCashSheet(viewModel: viewModel, cash: cash, formatter: .init()) {},
            height: 420,
            named: "reconcile",
        )
        assertScreenSnapshot(
            of: WithdrawCashSheet(viewModel: viewModel, cash: cash, sources: viewModel.overview?.deposits ?? [], principal: "USD") {},
            height: 420,
            named: "withdraw",
        )
    }
}
