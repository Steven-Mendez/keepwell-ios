import Domain
import DomainSamples
import Foundation
import RecurringDomain
import SharedPresentation
import Testing
@testable import RecurringPresentation

/// A rule's row while a draft it made waits: its state instead of the next date, and "Confirm"
/// doing what it does on Home (confirmed at once, with "Undo").
@Suite("Recurring row with a pending draft")
@MainActor
struct RecurringPendingDraftRowTests {
    private typealias IDs = SampleData.IDs
    private let today = SampleData.defaultReferenceDate

    private struct NoDeletions: UndoDeleteTransactionUseCase {
        func execute(id _: UUID) async -> Bool {
            false
        }
    }

    private func draft(daysAgo: Int) -> Transaction {
        Transaction(
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: today) ?? today,
            status: .planned,
            description: "Streaming",
            kind: .expense,
            categoryID: "subscriptions",
            amount: Decimal(string: "15.99") ?? 0,
            currency: "USD",
            accountID: IDs.mastercard,
            cardID: IDs.mastercardHolder,
            exchangeRate: SampleData.standard.settings.currencies.exchangeRate,
            recurringID: IDs.streamingRule,
        )
    }

    private func viewModel(store: InMemoryStore, undo: MovementUndo? = nil) -> RecurringViewModel {
        let now = today
        return RecurringViewModel(
            getOverview: RecurringPreview.useCases(store: store).overview,
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store, now: { now }),
            undo: undo,
            now: { now },
        )
    }

    @Test
    func withoutADraftTheRowShowsTheNextDate() async throws {
        let model = viewModel(store: InMemoryStore(sample: .standard))
        await model.load()
        let streaming = try #require(model.overview?.rule(IDs.streamingRule))
        #expect(model.pendingDraft(of: streaming) == nil)
        #expect(model.subtitle(of: streaming).hasPrefix("Every month · Tomorrow · "))
    }

    @Test
    func anOverdueDraftTakesTheDatesPlace() async throws {
        let store = InMemoryStore(sample: .standard)
        let waiting = draft(daysAgo: 3)
        await store.save(waiting)
        let model = viewModel(store: store)
        await model.load()
        let streaming = try #require(model.overview?.rule(IDs.streamingRule))
        let pending = try #require(model.pendingDraft(of: streaming))
        #expect(pending.transaction.id == waiting.id)
        #expect(pending.daysOverdue == 3)
        #expect(model.pendingLabel(pending) == "Overdue · 3 days")
        #expect(!model.subtitle(of: streaming).contains("Tomorrow"))
        #expect(model.subtitle(of: streaming).hasPrefix("Every month · "))
    }

    @Test
    func todaysDraftWaitsToBeConfirmed() async throws {
        let store = InMemoryStore(sample: .standard)
        await store.save(draft(daysAgo: 0))
        let model = viewModel(store: store)
        await model.load()
        let streaming = try #require(model.overview?.rule(IDs.streamingRule))
        let pending = try #require(model.pendingDraft(of: streaming))
        #expect(pending.daysOverdue == 0)
        #expect(model.pendingLabel(pending).hasPrefix("To confirm · "))
    }

    @Test
    func confirmingFromTheRowConfirmsItAndUndoMakesItADraftAgain() async throws {
        let store = InMemoryStore(sample: .standard)
        let waiting = draft(daysAgo: 2)
        await store.save(waiting)
        let undo = MovementUndo(undoDelete: NoDeletions(), unconfirm: DefaultUnconfirmTransactionUseCase(transactions: store))
        let model = viewModel(store: store, undo: undo)
        await model.load()
        let streaming = try #require(model.overview?.rule(IDs.streamingRule))
        let pending = try #require(model.pendingDraft(of: streaming))

        await model.confirm(pending)
        let confirmed = try #require(await store.fetchTransactions(in: nil).first { $0.id == waiting.id })
        #expect(confirmed.isConfirmed)
        #expect(confirmed.date == waiting.date)
        #expect(model.pendingDraft(of: streaming) == nil)
        #expect(model.confirming.isEmpty)
        let offer = try #require(undo.offer)
        #expect(offer.action == .confirm(waiting.id, plannedDate: waiting.date))

        await undo.undo(offer)
        await model.load()
        let restored = try #require(await store.fetchTransactions(in: nil).first { $0.id == waiting.id })
        #expect(restored == waiting)
        #expect(model.pendingDraft(of: streaming)?.transaction.id == waiting.id)
    }
}
