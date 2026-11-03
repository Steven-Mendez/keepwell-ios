import Foundation
import Testing
@testable import Core

@Suite("Widget snapshot store")
struct WidgetSnapshotStoreTests {
    /// A suite per test, so parallel tests never read each other's snapshot.
    private let suiteName = "test.widgets.\(UUID().uuidString)"

    private let snapshot = WidgetSnapshot(
        monthTitle: "November", spent: "C$7,500.00", spentCaption: "spent · 2 planned", spentFraction: 0.29,
        netWorthTitle: "Net worth", netWorth: "$11,157.46", netWorthCaption: "November: 71% saved",
        balances: [.init(title: "Bank", value: "$9,306"), .init(title: "Cash", value: "C$8,420")],
        shortcutsTitle: "Log quickly",
        shortcuts: [.init(categoryID: "groceries", title: "Groceries")],
        updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
    )

    @Test
    func whatTheAppSavesIsWhatTheWidgetLoads() {
        let app = WidgetSnapshotStore(suiteName: suiteName)
        let widget = WidgetSnapshotStore(suiteName: suiteName)
        #expect(widget.load() == nil)
        app.save(snapshot)
        #expect(widget.load() == snapshot)
    }

    @Test
    func aNewerSnapshotReplacesTheOldOne() {
        let store = WidgetSnapshotStore(suiteName: suiteName)
        store.save(snapshot)
        let newer = WidgetSnapshot(
            monthTitle: "December", spent: "$0.00", spentCaption: "spent", spentFraction: 0,
            netWorthTitle: "Net worth", netWorth: "$0.00", netWorthCaption: nil, balances: [],
            shortcutsTitle: "Log quickly", shortcuts: [], updatedAt: .now,
        )
        store.save(newer)
        #expect(store.load() == newer)
    }

    @Test
    func clearingRemovesTheSnapshotAndPendingQuickLog() {
        let store = WidgetSnapshotStore(suiteName: suiteName)
        store.save(snapshot)
        store.requestQuickLog(categoryID: "groceries")
        store.clear()
        #expect(store.load() == nil)
        #expect(store.takeQuickLogRequest() == nil)
    }

    @Test
    func aQuickLogRequestIsTakenOnce() {
        let store = WidgetSnapshotStore(suiteName: suiteName)
        store.requestQuickLog(categoryID: nil)
        #expect(store.takeQuickLogRequest() == .some(nil))
        #expect(store.takeQuickLogRequest() == nil)
    }

    @Test
    func withoutAGroupNothingIsSharedOrStored() {
        let store = WidgetSnapshotStore(suiteName: nil)
        store.save(snapshot)
        #expect(!store.isShared)
        #expect(store.load() == nil)
    }
}
