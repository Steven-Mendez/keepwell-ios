import CloudAccountDomain
import DesignSystem
import FeatureTestSupport
import SwiftUI
import Testing
@testable import CloudAccountPresentation

private struct Load: LoadCloudAccountUseCase {
    let user: CloudAccountUser?
    func execute() async throws(CloudAccountError) -> CloudAccountUser? {
        user
    }
}

private struct NoSignIn: SignInWithAppleUseCase {
    func execute(_: AppleCredential) async throws(CloudAccountError) -> CloudAccountUser {
        throw .unreachable
    }
}

private struct NoSignOut: SignOutUseCase {
    func execute(everywhere _: Bool) async throws(CloudAccountError) {}
}

private struct NoDelete: DeleteCloudAccountUseCase {
    func execute() async throws(CloudAccountError) {}
}

/// The account's pieces of Settings, laid out as Settings places them, and the first-sync choice.
@Suite("Account in Settings snapshots")
@MainActor
struct CloudAccountSettingsSnapshotTests {
    private let steven = CloudAccountUser(
        id: "u1", name: "Steven Mendez", email: "steven@example.com",
        capabilities: ["cloud_sync", "mcp"], earlyAccess: ["cloud_sync"],
    )

    private func model(_ user: CloudAccountUser?, sync: SyncCoordinator? = nil) async -> CloudAccountViewModel {
        let model = CloudAccountViewModel(load: Load(user: user), signIn: NoSignIn(), signOut: NoSignOut(), delete: NoDelete(), sync: sync)
        await model.refresh()
        return model
    }

    private func pieces(_ model: CloudAccountViewModel) -> some View {
        VStack(alignment: .leading, spacing: KWSpacing.lg) {
            CloudAccountHeader(viewModel: model)
            KWGroupedCard { CloudSyncRow(viewModel: model) }
            CloudAccountSections(viewModel: model)
            CloudAccountDestructiveRows(viewModel: model)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, KWLayout.gutter)
        .padding(.top, KWSpacing.xl)
    }

    private let conflict = SyncConflict(
        device: SyncDataSummary(movements: 12, accounts: 3),
        account: SyncDataSummary(movements: 248, accounts: 5, recurring: 4, goals: 1, loans: 1),
    )

    @Test
    func signedOutOffersSignIn() async {
        await assertScreenSnapshot(of: pieces(model(nil)), height: 520)
    }

    @Test
    func signedOutOffersSignInLight() async {
        await assertScreenSnapshot(of: pieces(model(nil)), height: 520, named: "light", colorScheme: .light)
    }

    @Test
    func signedInShowsTheProfileAndTheRedRows() async {
        await assertScreenSnapshot(of: pieces(model(steven)), height: 760)
    }

    @Test
    func signedInShowsTheProfileAndTheRedRowsLight() async {
        await assertScreenSnapshot(of: pieces(model(steven)), height: 760, named: "light", colorScheme: .light)
    }

    private func paused() async throws -> SyncCoordinator {
        let conflict = conflict
        let sync = SyncCoordinator(run: { _ in .needsChoice(conflict) }, status: { (nil, 0) })
        sync.trigger(after: 0)
        for _ in 0 ..< 300 where sync.conflict == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        return sync
    }

    /// "Decide later": Settings' sync row leads back to the choice.
    @Test
    func aPendingChoiceShowsInTheSyncRow() async throws {
        let sync = try await paused()
        await assertScreenSnapshot(of: pieces(model(steven, sync: sync)), height: 760)
    }

    @Test
    func theChoiceBetweenBothSides() async throws {
        try await assertScreenSnapshot(of: SyncChoiceSheet(sync: paused(), conflict: conflict))
    }

    @Test
    func theChoiceBetweenBothSidesLight() async throws {
        try await assertScreenSnapshot(of: SyncChoiceSheet(sync: paused(), conflict: conflict), named: "light", colorScheme: .light)
    }

    @Test
    func theChoiceOnASmallIPhoneWithLargeText() async throws {
        try await assertScreenSnapshot(
            of: SyncChoiceSheet(sync: paused(), conflict: conflict).environment(\.dynamicTypeSize, .xxxLarge),
            width: 320,
            height: 1000,
            named: "small",
        )
    }

    @Test
    func countsReadAsInTheSpec() {
        let counts = { (summary: SyncDataSummary) in SyncChoiceSheet.counts(summary).replacingOccurrences(of: "\u{00A0}", with: " ") }
        #expect(counts(SyncDataSummary(movements: 12, accounts: 3)) == "12 movements · 3 accounts")
        #expect(
            counts(SyncDataSummary(movements: 1, accounts: 1, cards: 4, goals: 2, loans: 1, debts: 1, rules: 1))
                == "1 movement · 1 account · 2 goals · 2 debts · 1 rule",
        )
    }
}
