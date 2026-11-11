import CloudAccountData
import CloudAccountDomain
import Domain
import Foundation
import Testing

/// The first sync of this device with an account: who has data decides what happens.
extension SyncEngineTests {
    private static func row(_ id: String, name: String = "Row", deleted: Bool = false) -> [String: Any] {
        [
            "id": id, "name": name, "created_at": "2026-11-01T00:00:00.000Z", "updated_at": "2026-11-01T00:00:00.000Z",
            "deleted_at": deleted ? "2026-11-02T00:00:00.000Z" : NSNull(),
        ]
    }

    /// Serves a snapshot with `rows` per entity, and empty pushes and pulls.
    private static func serve(_ rows: [String: [[String: Any]]]) {
        StubProtocol.handler = { request in
            switch request.url?.path {
            case "/sync/snapshot":
                let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
                let entity = query.first { $0.name == "entity" }?.value ?? ""
                return (200, [:], json(["rows": rows[entity] ?? [], "server_seq": 7, "next_after": NSNull()]))
            case "/sync/push":
                // The body arrives as a stream; StubProtocol records it before asking for an answer.
                let sent = StubProtocol.requests.last?.httpBody ?? request.httpBody
                let body = sent.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                let events = body?["events"] as? [[String: Any]] ?? []
                let results = events.map { ["event_id": $0["event_id"] ?? "", "status": "applied"] }
                return (200, [:], json(["results": results, "partial": false]))
            default:
                return (200, [:], json(["changes": [], "next_cursor": 7, "has_more": false]))
            }
        }
    }

    private func paths() -> [String] {
        StubProtocol.requests.compactMap(\.url?.path)
    }

    @Test
    func bothSidesWithDataStopForAChoiceWithoutSendingOrApplyingAnything() async throws {
        let store = FakeSyncStore(events: [event("groceries", name: "Mine")], counts: ["transaction": 12, "account": 3])
        let suite = suite()
        Self.serve([
            "account": [Self.row("a1"), Self.row("a2", deleted: true)],
            "transaction": [Self.row("t1"), Self.row("t2")],
            "category": [Self.row("food")],
        ])
        let outcome = try await engine(store, suite: suite).syncOnce(account: "u1")
        let expected = SyncConflict(
            device: SyncDataSummary(movements: 12, accounts: 3),
            account: SyncDataSummary(movements: 2, accounts: 1),
        )
        #expect(outcome == .needsChoice(expected))
        #expect(!paths().contains("/sync/push"))
        #expect(!paths().contains("/sync/pull"))
        #expect(await store.appliedCount() == 0)
        #expect(await store.pendingCount() == 1)
        #expect(cursor(suite) == nil)
    }

    @Test
    func onlyTheAccountHasDataSoItComesDownWholeWithoutAsking() async throws {
        // The onboarding's categories wait in the outbox; the account's replace them.
        let store = FakeSyncStore(events: [event("groceries", name: "Mine")], counts: ["account": 0])
        let suite = suite()
        Self.serve(["account": [Self.row("a1")], "category": [Self.row("food")]])
        let outcome = try await engine(store, suite: suite).syncOnce(account: "u1")
        #expect(outcome == .synced)
        #expect(await store.replacedWith?.map(\.entity) == ["account", "category"])
        #expect(!paths().contains("/sync/push"))
        #expect(cursor(suite) == 7)
    }

    @Test
    func onlyThisDeviceHasDataSoItGoesUpAsBefore() async throws {
        let store = FakeSyncStore(events: [event("groceries", name: "Mine")], counts: ["transaction": 4])
        let suite = suite()
        // Categories and settings in the account aren't user data.
        Self.serve(["category": [Self.row("food", name: "Food")], "settings": [Self.row("settings")]])
        let outcome = try await engine(store, suite: suite).syncOnce(account: "u1")
        #expect(outcome == .synced)
        #expect(await store.replacedWith == nil)
        #expect(paths().contains("/sync/push"))
        #expect(await store.pendingCount() == 0)
        #expect(await store.appliedNames().contains("Food"))
        #expect(cursor(suite) == 7)
    }

    @Test
    func laterSyncsNeverAskAgain() async throws {
        let store = FakeSyncStore(counts: ["transaction": 4])
        let suite = suite()
        UserDefaults(suiteName: suite)?.set(3, forKey: "sync.cursor")
        Self.serve(["transaction": [Self.row("t1")]])
        let outcome = try await engine(store, suite: suite).syncOnce(account: "u1")
        #expect(outcome == .synced)
        #expect(!paths().contains("/sync/snapshot"))
    }

    @Test
    func anotherAccountStartsWithItsOwnFirstSync() async throws {
        let store = FakeSyncStore(counts: ["transaction": 4])
        let suite = suite()
        UserDefaults(suiteName: suite)?.set(3, forKey: "sync.cursor")
        UserDefaults(suiteName: suite)?.set("u1", forKey: "sync.account")
        Self.serve(["transaction": [Self.row("t1")]])
        let outcome = try await engine(store, suite: suite).syncOnce(account: "u2")
        #expect(outcome == .needsChoice(SyncConflict(device: SyncDataSummary(movements: 4), account: SyncDataSummary(movements: 1))))
    }

    @Test
    func usingTheAccountsDataReplacesThisDeviceAndSyncsOn() async throws {
        let store = FakeSyncStore(events: [event("groceries", name: "Mine")], counts: ["transaction": 4])
        let suite = suite()
        Self.serve(["transaction": [Self.row("t1")], "settings": [Self.row("settings")]])
        try await engine(store, suite: suite).resolve(.useAccount, account: "u1")
        #expect(await store.replacedWith?.map(\.entity) == ["settings", "transaction"])
        #expect(await store.uploadedOver == nil)
        #expect(cursor(suite) == 7)
        #expect(paths().last == "/sync/pull")
    }

    @Test
    func keepingThisDevicesDataSendsTheUploadAndThenSyncsOn() async throws {
        let store = FakeSyncStore(counts: ["transaction": 4])
        let suite = suite()
        Self.serve(["transaction": [Self.row("t1")], "account": [Self.row("a1")]])
        try await engine(store, suite: suite).resolve(.keepDevice, account: "u1")
        #expect(await store.uploadedOver?.count == 2)
        #expect(await store.replacedWith == nil)
        let push = try #require(StubProtocol.requests.first { $0.url?.path == "/sync/push" })
        let body = try #require(push.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        let operations = (body["events"] as? [[String: Any]])?.compactMap { $0["operation"] as? String }
        #expect(operations == ["delete", "delete"])
        #expect(await store.pendingCount() == 0)
        #expect(cursor(suite) == 7)
    }

    /// Older versions left a choice marker behind when the app quit mid-download, and finished it
    /// on the next round by clearing the iPhone again, entries made since included.
    @Test
    func aChoiceLeftByAnOlderVersionNeverWipesWithoutAsking() async throws {
        let store = FakeSyncStore(counts: ["transaction": 2])
        let suite = suite()
        UserDefaults(suiteName: suite)?.set("useAccount", forKey: "sync.choosing")
        Self.serve(["transaction": [Self.row("t1"), Self.row("t2")]])
        let outcome = try await engine(store, suite: suite).syncOnce(account: "u1")
        #expect(outcome == .needsChoice(SyncConflict(device: SyncDataSummary(movements: 2), account: SyncDataSummary(movements: 2))))
        #expect(await store.replacedWith == nil)
        #expect(cursor(suite) == nil)
        #expect(UserDefaults(suiteName: suite)?.string(forKey: "sync.choosing") == nil)
    }

    /// Nothing local is touched before the account's whole snapshot is in hand.
    @Test
    func aSnapshotThatCantBeFetchedChangesNothingOnThisDevice() async {
        let store = FakeSyncStore(events: [event("groceries", name: "Mine")], counts: ["transaction": 4])
        let suite = suite()
        StubProtocol.handler = { _ in (500, [:], Self.json([:])) }
        let eng = engine(store, suite: suite)
        await #expect(throws: CloudAccountError.self) { try await eng.resolve(.useAccount, account: "u1") }
        await #expect(throws: CloudAccountError.self) { try await eng.syncOnce(account: "u1") }
        #expect(await store.replacedWith == nil)
        #expect(await store.uploadedOver == nil)
        #expect(await store.pendingCount() == 1)
        #expect(cursor(suite) == nil)
    }

    /// A row the store can't read fails the download, so the cursor never moves past it.
    @Test
    func aRowThatCantBeStoredFailsTheFirstDownloadWithoutACursor() async {
        let store = FakeSyncStore()
        await store.setFailsToReplace(true)
        let suite = suite()
        Self.serve(["transaction": [Self.row("t1")]])
        await #expect(throws: CloudAccountError.server(code: "apply_failed", requestID: nil)) {
            try await engine(store, suite: suite).syncOnce(account: "u1")
        }
        #expect(cursor(suite) == nil)
        #expect(!paths().contains("/sync/push"))
    }

    @Test
    func aRowThatCantBeStoredFailsUsingTheAccountsDataWithoutACursor() async {
        let store = FakeSyncStore(events: [event("groceries", name: "Mine")], counts: ["transaction": 4])
        await store.setFailsToReplace(true)
        let suite = suite()
        Self.serve(["transaction": [Self.row("t1")]])
        await #expect(throws: CloudAccountError.server(code: "apply_failed", requestID: nil)) {
            try await engine(store, suite: suite).resolve(.useAccount, account: "u1")
        }
        #expect(cursor(suite) == nil)
        #expect(await store.pendingCount() == 1)
    }

    /// An empty account after this device's outbox was already sent elsewhere (another account):
    /// nothing is queued, so the device's rows are put in the outbox before the snapshot is adopted.
    @Test
    func anEmptyAccountGetsThisDevicesDataAndKeepsItsOwnChanges() async throws {
        let store = FakeSyncStore(events: [event("food", name: "Mine")], counts: ["transaction": 4])
        let suite = suite()
        Self.serve(["category": [Self.row("food", name: "Theirs"), Self.row("rent", name: "Rent")]])
        let outcome = try await engine(store, suite: suite).syncOnce(account: "u2")
        #expect(outcome == .synced)
        #expect(await store.uploadedOver?.isEmpty == true)
        #expect(await store.replacedWith == nil)
        // The device's own change is pending, so the account's row for it didn't overwrite it.
        #expect(await store.appliedNames() == ["Rent"])
        #expect(paths().contains("/sync/push"))
        #expect(await store.pendingCount() == 0)
        #expect(cursor(suite) == 7)
    }

    @Test
    func resettingForgetsTheCursorSoTheNextSyncIsAFirstSyncAgain() async {
        let store = FakeSyncStore()
        let suite = suite()
        UserDefaults(suiteName: suite)?.set(3, forKey: "sync.cursor")
        let engine = engine(store, suite: suite)
        await engine.reset()
        #expect(cursor(suite) == nil)
    }

    // MARK: - Concurrent snapshot

    private static let order = [
        "settings", "account", "card", "category", "transaction", "recurringRule", "savingsGoal", "loan", "loanPayment",
        "personalDebt", "personalDebtRepayment", "categorizationRule",
    ]

    /// One row per entity, two pages for transactions, and later entities answering first: whatever
    /// finishes first, the rows must come out as a sequential fetch would have produced them.
    private static func serveStaggered(failing: String? = nil) {
        StubProtocol.peakInFlight = 0
        // Earlier entities answer last, so a sequential reading of the answers would come out reversed.
        StubProtocol.delayFor = { request in
            let entity = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?
                .first { $0.name == "entity" }?.value
            return Double(order.count - (order.firstIndex { $0 == entity } ?? 0)) * 0.02
        }
        StubProtocol.handler = { request in
            let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
            func value(_ name: String) -> String {
                query.first { $0.name == name }?.value ?? ""
            }
            guard request.url?.path == "/sync/snapshot" else {
                return (200, [:], json(["changes": [], "next_cursor": 7, "has_more": false, "results": [], "partial": false]))
            }
            let entity = value("entity")
            let position = order.firstIndex(of: entity) ?? 0
            if entity == failing {
                return (500, [:], Data())
            }
            // Each entity reports its own sequence: the cursor is the lowest, as in a sequential fetch.
            let seq = 100 - position
            if entity == "transaction" {
                if value("after").isEmpty {
                    return (
                        200,
                        [:],
                        json(["rows": [row("transaction-1"), row("transaction-2")], "server_seq": seq, "next_after": "transaction-2"]),
                    )
                }
                return (200, [:], json(["rows": [row("transaction-3")], "server_seq": seq, "next_after": NSNull()]))
            }
            return (200, [:], json(["rows": [row("\(entity)-1")], "server_seq": seq, "next_after": NSNull()]))
        }
    }

    @Test
    func theConcurrentSnapshotAppliesRowsInTheSequentialOrder() async throws {
        let store = FakeSyncStore()
        let suite = suite()
        Self.serveStaggered()
        defer { StubProtocol.delayFor = nil }
        try await engine(store, suite: suite).syncOnce(account: "u1")

        let rows = try #require(await store.replacedWith)
        var expected: [String] = []
        for entity in Self.order {
            expected += entity == "transaction" ? ["transaction-1", "transaction-2", "transaction-3"] : ["\(entity)-1"]
        }
        let ids = rows.compactMap { (try? JSONSerialization.jsonObject(with: $0.row) as? [String: Any])?["id"] as? String }
        #expect(ids == expected)
        #expect(rows.map(\.entity).first == "settings")
        // The pull starts from the lowest sequence among entities, so a change made while downloading is caught.
        let pull = try #require(StubProtocol.requests.last { $0.url?.path == "/sync/pull" })
        #expect(pull.url?.query?.contains("cursor=\(100 - (Self.order.count - 1))") == true)
        #expect(StubProtocol.requests.filter { $0.url?.path == "/sync/snapshot" }.count == Self.order.count + 1)
    }

    @Test
    func theSnapshotDownloadsSeveralEntitiesAtOnceButNeverMoreThanTheCap() async throws {
        Self.serveStaggered()
        defer { StubProtocol.delayFor = nil }
        try await engine(FakeSyncStore(), suite: suite()).syncOnce(account: "u1")
        #expect(StubProtocol.peakInFlight > 1)
        #expect(StubProtocol.peakInFlight <= SyncEngine.snapshotConcurrency)
    }

    @Test
    func oneEntityFailingFailsTheWholeSnapshotAndAppliesNothing() async throws {
        let store = FakeSyncStore()
        let suite = suite()
        Self.serveStaggered(failing: "loan")
        defer { StubProtocol.delayFor = nil }
        do {
            try await engine(store, suite: suite).syncOnce(account: "u1")
            Issue.record("The sync should have failed")
        } catch {
            #expect(error == .server(code: "http_500", requestID: nil))
        }
        #expect(await store.replacedWith == nil)
        #expect(await store.appliedCount() == 0)
        #expect(await store.pendingCount() == 0)
        #expect(cursor(suite) == nil)
        #expect(!paths().contains("/sync/push"))
        #expect(!paths().contains("/sync/pull"))
    }
}
