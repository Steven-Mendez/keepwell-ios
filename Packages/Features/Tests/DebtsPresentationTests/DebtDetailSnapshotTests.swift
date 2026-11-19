import DebtsDomain
import Domain
import DomainSamples
import FeatureTestSupport
import Foundation
import SwiftUI
import Testing
@testable import DebtsPresentation

/// A personal debt's detail: what they owe offers "Deposit into account" for a repayment, with its
/// note once an account is chosen; what the person owes only records it.
@Suite("Debt detail snapshots")
@MainActor
struct DebtDetailSnapshotTests {
    private let now = SampleData.defaultReferenceDate
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func detail(_ id: UUID) async throws -> DebtDetailViewModel {
        let store = InMemoryStore(sample: .standard)
        let debt = try #require(await store.fetchPersonalDebts().first { $0.id == id })
        let viewModel = DebtDetailViewModel(
            debt: debt, useCases: DebtsPreview.useCases(store: store, now: now), calendar: calendar, now: { [now] in now },
        )
        await viewModel.load()
        return viewModel
    }

    private func screen(_ viewModel: DebtDetailViewModel) -> some View {
        DebtDetailView(viewModel: viewModel, hidesBalances: false, onEdit: {}, onDone: {}, onClose: {})
    }

    @Test
    func repaymentDepositedIntoAnAccount() async throws {
        let viewModel = try await detail(SampleData.IDs.juanDebt)
        viewModel.repaymentText = "100"
        viewModel.depositAccountID = SampleData.IDs.cash
        assertScreenSnapshot(of: screen(viewModel))
    }

    @Test
    func whatYouOweHasNoDeposit() async throws {
        let viewModel = try await detail(SampleData.IDs.anaDebt)
        assertScreenSnapshot(of: screen(viewModel))
    }
}
