import DebtsDomain
import Domain
import DomainSamples
import FeatureTestSupport
import Foundation
import SwiftUI
import Testing
@testable import DebtsPresentation

/// A split expense's people: what is left to collect, who paid (green, struck through) and the
/// public link; once everyone paid, "Everyone paid".
@Suite("Split detail snapshots")
@MainActor
struct SplitDetailSnapshotTests {
    private let now = SampleData.defaultReferenceDate

    private func detail(payEveryone: Bool) async throws -> SplitDetailViewModel {
        let store = InMemoryStore(sample: .standard)
        let expense = Transaction(
            date: now, description: "Los Taki Pollos", kind: .expense, categoryID: "restaurants", amount: 1156.25, currency: "NIO",
            accountID: SampleData.IDs.cash, exchangeRate: .single("NIO"), shareToken: "AbCdEfGhIjKlMnOpQrSt_-",
        )
        try await store.save(expense)
        let split = DefaultSplitTransactionUseCase(transactions: store, debts: store)
        let created = try await split.execute(transactionID: expense.id, shares: [
            SplitShare(person: "Lía", amount: Decimal(string: "511.88") ?? 0),
            SplitShare(person: "Mario", amount: Decimal(string: "247.37") ?? 0),
            SplitShare(person: "Tete", amount: Decimal(string: "149.62") ?? 0),
        ])
        let useCases = DebtsPreview.useCases(store: store, now: now)
        for debt in payEveryone ? created : [created[2]] {
            try await useCases.updateDebt.repay(id: debt.id, amount: debt.amount.amount, on: now)
        }
        let viewModel = try SplitDetailViewModel(
            transaction: expense, split: split, useCases: useCases, web: #require(URL(string: "https://keepwell.app")),
            now: { [now] in now },
        )
        await viewModel.load()
        return viewModel
    }

    @Test
    func someStillOwe() async throws {
        try await assertScreenSnapshot(of: SplitDetailView(viewModel: detail(payEveryone: false), onEditSplit: {}, onClose: {}))
    }

    @Test
    func everyonePaid() async throws {
        try await assertScreenSnapshot(of: SplitDetailView(viewModel: detail(payEveryone: true), onEditSplit: {}, onClose: {}))
    }
}
