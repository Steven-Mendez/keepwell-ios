import Domain
import DomainSamples
import FeatureTestSupport
import Foundation
import RecurringDomain
import SharedPresentation
import SwiftUI
import Testing
@testable import RecurringPresentation

/// A rule's detail: whether this cycle is paid, linking a payment recorded by hand and taking it out.
@Suite("Recurring rule detail")
@MainActor
struct RecurringRuleDetailTests {
    private typealias IDs = SampleData.IDs
    private let today = SampleData.defaultReferenceDate

    /// A streaming charge typed by hand `daysAgo` days back, linked to no rule.
    private func charge(
        daysAgo: Int,
        amount: String = "15.99",
        description: String = "STREAMING.COM",
        status: TransactionStatus = .confirmed,
    ) -> Domain.Transaction {
        Domain.Transaction(
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: today) ?? today,
            status: status,
            description: description,
            kind: .expense,
            categoryID: "subscriptions",
            amount: Decimal(string: amount) ?? 0,
            currency: "USD",
            accountID: IDs.mastercard,
            cardID: IDs.mastercardHolder,
            exchangeRate: SampleData.standard.settings.currencies.exchangeRate,
        )
    }

    private func loaded(_ store: InMemoryStore) async -> RecurringRuleDetailViewModel {
        let model = RecurringPreview.detailViewModel(ruleID: IDs.streamingRule, store: store)
        await model.load()
        return model
    }

    @Test
    func aRuleWithNothingLinkedIsUpcomingAndOffersTheChargeThatMatches() async {
        let store = InMemoryStore(sample: .standard)
        let manual = charge(daysAgo: 20)
        await store.save(manual)
        let model = await loaded(store)
        #expect(model.status?.state == .upcoming)
        #expect(model.stateLabel == "Upcoming")
        #expect(model.nextPayment == "Tomorrow")
        #expect(model.suggested.map(\.id).contains(manual.id))
        #expect(!model.others.map(\.id).contains(manual.id))
    }

    @Test
    func linkingAChargePaysTheCycleAndUnlinkingTakesItOut() async throws {
        let store = InMemoryStore(sample: .standard)
        let manual = charge(daysAgo: 20)
        await store.save(manual)
        let model = await loaded(store)
        let nextDate = model.rule?.nextDate

        #expect(await model.link(manual.id))
        #expect(model.status?.state == .paid)
        #expect(model.stateLabel.hasPrefix("Paid · "))
        #expect(model.history?.payments.map(\.id) == [manual.id])
        #expect(model.paymentsCount == "1 payment")
        // Linking says what paid it; the schedule stays where it was.
        #expect(model.rule?.nextDate == nextDate)
        let stored = try #require(await store.fetchTransactions(in: nil).first { $0.id == manual.id })
        #expect(stored.recurringID == IDs.streamingRule)

        await model.unlink(manual.id)
        #expect(model.status?.state == .upcoming)
        #expect(model.history?.payments.isEmpty == true)
        let unlinked = try #require(await store.fetchTransactions(in: nil).first { $0.id == manual.id })
        #expect(unlinked == manual)
    }

    @Test
    func aMovementOfAnotherKindCannotBeLinked() async {
        let store = InMemoryStore(sample: .standard)
        let income = Domain.Transaction(
            date: today, description: "Refund", kind: .income, categoryID: "salary", amount: Decimal(string: "15.99") ?? 0,
            currency: "USD", accountID: IDs.mastercard, exchangeRate: SampleData.standard.settings.currencies.exchangeRate,
        )
        await store.save(income)
        let model = await loaded(store)
        #expect(!model.suggested.map(\.id).contains(income.id))
        #expect(await model.link(income.id) == false)
        #expect(model.actionError != nil)
    }

    @Test
    func theSearchNarrowsWhatCanBeLinked() async {
        let store = InMemoryStore(sample: .standard)
        let manual = charge(daysAgo: 20)
        await store.save(manual)
        let model = await loaded(store)
        model.query = "streaming.com"
        #expect(model.suggested.map(\.id) == [manual.id])
        model.query = "no such movement"
        #expect(model.suggested.isEmpty)
        #expect(model.others.isEmpty)
    }

    @Test
    func theListRowSaysPaidAndMovesTheNextDateBesideTheFrequency() async throws {
        let store = InMemoryStore(sample: .standard)
        let manual = charge(daysAgo: 20)
        await store.save(manual)
        try await RecurringPreview.useCases(store: store).linkPayment.execute(transactionID: manual.id, ruleID: IDs.streamingRule)
        let list = RecurringPreview.listViewModel(store: store)
        await list.load()
        let streaming = try #require(list.overview?.rule(IDs.streamingRule))
        #expect(list.paidLabel(of: streaming)?.hasPrefix("Paid · ") == true)
        #expect(list.subtitle(of: streaming).hasPrefix("Every month · Next Tomorrow · "))
    }

    @Test
    func aDeletedRuleLeavesNothingToShow() async throws {
        let store = InMemoryStore(sample: .standard)
        let model = await loaded(store)
        try await store.deleteRecurringRule(id: IDs.streamingRule)
        await model.load()
        #expect(model.state == .missing)
    }

    @Test
    func detailOfAPaidRuleSnapshot() async throws {
        let store = InMemoryStore(sample: .standard)
        // Two charges at the old price and the latest at the new one, all linked.
        for (daysAgo, amount) in [(81, "13.99"), (51, "13.99"), (20, "15.99")] {
            let manual = charge(daysAgo: daysAgo, amount: amount, description: "Streaming")
            await store.save(manual)
            try await RecurringPreview.useCases(store: store).linkPayment.execute(transactionID: manual.id, ruleID: IDs.streamingRule)
        }
        let model = await loaded(store)
        assertScreenSnapshot(
            of: RecurringRuleDetailView(viewModel: model, onBack: {}, onEdit: {}, onOpenTransaction: { _ in }),
            height: 1000,
        )
    }

    @Test
    func detailWithoutPaymentsSnapshot() async {
        let model = await loaded(InMemoryStore(sample: .standard))
        assertScreenSnapshot(
            of: RecurringRuleDetailView(viewModel: model, onBack: {}, onEdit: {}, onOpenTransaction: { _ in }),
            height: 900,
        )
    }

    @Test
    func linkAPaymentSheetSnapshot() async {
        let store = InMemoryStore(sample: .standard)
        await store.save(charge(daysAgo: 20))
        let model = await loaded(store)
        assertScreenSnapshot(
            of: RecurringLinkPaymentSheet(viewModel: model) {}.background(KWSnapshotBackground()),
            height: 900,
        )
    }
}

/// The sheet draws on the screen's background, which the sheet presentation supplies in the app.
private struct KWSnapshotBackground: View {
    var body: some View {
        Color.black
    }
}
