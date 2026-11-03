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
            of: AccountsView(viewModel: viewModel, onAdd: {}, onOpenCreditCard: { _ in }, onLinkCard: { _ in }),
            height: 1500,
        )
    }

    @Test
    func bankAccountWithoutCardShowsAnEmptySlot() async throws {
        let viewModel = await AccountsFactory.loaded()
        let deposit = try #require(viewModel.overview?.deposits.first)
        let cardless = AccountsOverview.Deposit(account: deposit.account, balance: deposit.balance, debitCards: [])
        assertScreenSnapshot(of: DepositCards(deposit: cardless, formatter: .init()) {}.padding(16), height: 280)
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
