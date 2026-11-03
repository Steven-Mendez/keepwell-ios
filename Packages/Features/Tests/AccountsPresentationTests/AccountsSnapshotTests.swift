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
        assertScreenSnapshot(of: DepositCard(deposit: deposit, formatter: .init(), ownerName: "Steven") {}.padding(16), height: 280)
    }

    @Test
    func debitCardDetail() async {
        let viewModel = await DebitCardFactory.loaded()
        assertScreenSnapshot(
            of: DebitCardView(viewModel: viewModel, onBack: {}, onSeeAllMovements: { _ in }),
            height: 1500,
        )
    }
}
